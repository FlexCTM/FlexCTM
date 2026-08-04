program main
   !! 空气质量数值模式

   ! 内部模块
   use mod_namelist, only: config_type, load_config
   use mod_const, only: fp
   use mod_error, only: fatal_error
   use mod_block, only: block_type
   use mod_chem_type, only: chem_table_type
   use mod_chem_csv, only: load_chem_table
   use mod_mete_type, only: mete_table_type, mete_mapping_table_type
   use mod_mete_csv, only: load_mete_table, load_mete_mapping_table, validate_mete_mapping
   use mod_mete_diagnostic, only: diagnose_meteorology

   use mod_tool, only: get_filename

   use mod_emission, only: update_emission
   use mod_meteorology, only: read_mete_field, read_mete_static

   use mod_output, only: write_static_output, write_model_output

   use mod_initial, only: initialize_chemistry
   use mod_boundary, only: read_domain_boundary

   use mod_drive_adv, only: drive_hadv_by_ppm, drive_vadv_by_ppm, handle_domain_bc, cal_w_by_rho
   use mod_drive_diff, only: drive_hdiff_by_k_theory, drive_vdiff_by_k_theory

   ! 外部模块
   use parallel, only: west, east, south, north
   use parallel, only: grid_meta_type, process_type, fill_halo, avg_pole, get_bc_from_parent!, global_sum
   use datetime, only: datetime_type, create_datetime, timedelta_type, create_timedelta
   use projection, only: proj_type, create_proj, PROJ_SUCCESS

   implicit none

   integer :: proj_stat !! Status returned by projection construction. / 投影构造返回的状态码。
   integer :: i         !! Root-domain time-step index. / 根区域时间步下标。
   integer :: j         !! Nested-domain substep index. / 嵌套区域子时间步下标。
   integer :: n         !! Chemical or meteorological variable index. / 化学或气象变量下标。
   integer :: it        !! Chemistry time-window index. / 化学时间窗口下标。
   integer :: m         !! One-based domain index. / 一基区域下标。
   character(len=256) :: filename !! Expanded input/output path. / 展开占位符后的输入或输出路径。
   type(mete_table_type) :: mete_table !! 标准气象变量和公共诊断变量表。
   type(mete_mapping_table_type) :: mete_mapping !! WRF 接口映射表。
   type(chem_table_type) :: chem_meta  !! 污染物变量元信息
   type(datetime_type)  :: time0      !! 模式运行开始时间
   type(datetime_type)  :: new_time   !! 单次迭代开始时间
   type(datetime_type)  :: old_time   !! 单次迭代结束时间
   type(datetime_type)  :: this_time  !! 当前时间
   type(datetime_type)  :: next_time  !! 下一个时间
   type(datetime_type)  :: next_mete_time !! 下一个气象数据文件时间
   type(timedelta_type) :: timedelta !! 时间间隔
   real(fp) :: factor !! Linear meteorology interpolation weight [0,1]. / 气象场线性时间插值权重 [0,1]。

   type(grid_meta_type), allocatable :: grid_metas(:) !! 网格信息

   type(proj_type) :: p  !! 投影信息
   type(process_type) :: proc       !！ 当前进程信息，对MPI信息的封装
   type(block_type), allocatable :: blocks(:)  !! 当前进行需要处理的数据快，不同区域数据块不同
   type(config_type) :: cfg
   character(:), allocatable :: proj_message

   cfg = load_config()
   if (cfg%proj_id /= 0) then
      p = create_proj(cfg%proj_id, lon1=cfg%ref_lon, lat1=cfg%ref_lat, truelat1=cfg%truelat1, truelat2=cfg%truelat2, &
                      stat=proj_stat, errmsg=proj_message)
      if (proj_stat /= PROJ_SUCCESS) call fatal_error('invalid projection configuration: '//proj_message)
   end if

   ! 读取变量头信息
   chem_meta = load_chem_table(cfg%chem_meta_file)
   mete_table = load_mete_table(cfg%mete_table_file)
   if (trim(cfg%mete_source) == 'wrf') then
      mete_mapping = load_mete_mapping_table(cfg%mete_mapping_file)
      call validate_mete_mapping(mete_table, mete_mapping)
   end if

   ! 初始化MPI: 需要支持不同网格的配置
   allocate (grid_metas(cfg%ndom))
   do m = 1, cfg%ndom
      call grid_metas(m)%init(m, cfg%we(m), cfg%sn(m), cfg%nlev, cfg%i_parent_start(m), cfg%j_parent_start(m), &
                              cfg%parent_grid_ratio(m))
   end do
   call proc%init(grid_metas, cfg%nhalo, nvar=chem_meta%nvar, is_global=cfg%is_global)
   do m = 1, cfg%ndom
      if (proc%is_root()) write (*, *) '=================', m
      if (proc%is_root()) call proc%domains(m)%print_layout()
   end do

   ! 分配资源, 初始化网格信息
   allocate (blocks(cfg%ndom))
   do m = 1, cfg%ndom
      call blocks(m)%init(proc%bridges(m), proc%tiles(m), proc%domains(m)%nz, proc%nhalo, chem_meta, mete_table, cfg%twindow)
      blocks(m)%xorg = cfg%xorgs(m) + (proc%tiles(m)%ids - 1 - cfg%nhalo)*cfg%deltas(m) ! 考虑halo
      blocks(m)%yorg = cfg%yorgs(m) + (proc%tiles(m)%jds - 1 - cfg%nhalo)*cfg%deltas(m)
      call blocks(m)%mesh%init(blocks(m)%xorg, blocks(m)%yorg, cfg%deltas(m), blocks(m)%nx, blocks(m)%ny, cfg%proj_id, p)

      ! 交换边界处的网格信息
      call fill_halo(proc%tiles(m), blocks(m)%mesh%area)
      call fill_halo(proc%tiles(m), blocks(m)%mesh%xlen)
      call fill_halo(proc%tiles(m), blocks(m)%mesh%ylen)
   end do

   ! 初始化浓度场 .or. restart, 静态数据
   time0 = create_datetime(cfg%start_time, '%Y%m%d%H')
   do m = 1, cfg%ndom
      call initialize_chemistry(proc, proc%domains(m), proc%tiles(m), blocks(m), get_filename(cfg%ic_file, domain=cfg%dom_str(m)))

      ! 静态数据
      filename = time0%format(get_filename(cfg%mete_file, domain=cfg%dom_str(m)))
      call read_mete_static(cfg%mete_source, proc, proc%domains(m), proc%tiles(m), blocks(m), filename)

      ! 写出静态网格数据。
      filename = get_filename(cfg%static_grid_file, domain=cfg%dom_str(m))
      call write_static_output(proc, proc%domains(m), proc%tiles(m), blocks(m), filename)
   end do

   ! 时间迭代
   next_mete_time = time0 + create_timedelta(seconds=cfg%mete_timedelta)
   LOOP_TIME: do i = 0, cfg%nt - 1 !! 严格执行配置时长对应的 nt 个根区域时间步。
      old_time = time0 + create_timedelta(seconds=cfg%dt*i)  ! 积分开始时间
      new_time = old_time + create_timedelta(seconds=cfg%dt) ! 积分结束时间
      if (proc%is_root()) write (*, *) old_time%format('%Y-%m-%d-%H:%M'), ' --> ', new_time%format('%Y-%m-%d-%H:%M')
      ! 同步不同区域的数据, 读取气象数据+排放数据
      do m = 1, cfg%ndom
         if (.not. proc%domains(m)%is_global) then
            if (m == 1) then ! 更新边界: 需要气象数据和上一次时次的浓度数据
               if (old_time%minute == 0) call read_domain_boundary(proc%tiles(m), blocks(m), old_time%format(cfg%bc_file))
            else
               ! 从父区域收集当前区域的边界数据；使用父区域上一时刻的边界值。
               call get_bc_from_parent(proc, proc%bridges(m), blocks(cfg%parent_id(m))%chem3d(:, :, :, :, cfg%twindow), &
                                       blocks(m)%coarse_edges(west)%bc, blocks(m)%coarse_edges(east)%bc, &
                                       blocks(m)%coarse_edges(south)%bc, blocks(m)%coarse_edges(north)%bc)
            end if
         end if
         if (old_time%minute == 0) then  ! 读取气象数据
            if (old_time == time0) then ! 第一次迭代，需要读取两个气象数据
               filename = old_time%format(get_filename(cfg%mete_file, domain=cfg%dom_str(m)))
               call read_mete_field(cfg%mete_source, proc, proc%domains(m), proc%tiles(m), blocks(m), filename, mete_mapping)
               blocks(m)%mete2d_1 = blocks(m)%mete2d
               blocks(m)%mete3d_1 = blocks(m)%mete3d
            else
               blocks(m)%mete2d_1 = blocks(m)%mete2d_2
               blocks(m)%mete3d_1 = blocks(m)%mete3d_2
            end if
            next_mete_time = old_time + create_timedelta(seconds=cfg%mete_timedelta)
            filename = next_mete_time%format(get_filename(cfg%mete_file, domain=cfg%dom_str(m)))
            call read_mete_field(cfg%mete_source, proc, proc%domains(m), proc%tiles(m), blocks(m), filename, mete_mapping)
            blocks(m)%mete2d_2 = blocks(m)%mete2d
            blocks(m)%mete3d_2 = blocks(m)%mete3d
         end if

         ! 诊断质量守恒
         if (old_time%minute == 0) then  ! 更新排放数据(需要先更新气象数据, 单位转换)
            filename = old_time%format(get_filename(cfg%emis_file, domain=cfg%dom_str(m)))
            call update_emission(proc, proc%domains(m), proc%tiles(m), blocks(m), filename, cfg%emis_nlev)
         end if
      end do

      ! 物理化学过程
      LOOP_DOM: do m = 1, cfg%ndom ! 不同区域需要不同的迭代时间

         LOOP_INTEGRAL: do j = 1, cfg%nts(m) ! 高空间分辨率区域采用更小的积分时间步长。

            ! 更新气象数据: 做时间上的线性插值
            this_time = old_time + create_timedelta(seconds=cfg%dts(m)*(j - 1))
            timedelta = next_mete_time - this_time
            factor = timedelta%total_seconds()/cfg%mete_timedelta
            blocks(m)%mete2d = factor*blocks(m)%mete2d_1 + (1 - factor)*blocks(m)%mete2d_2
            blocks(m)%mete3d = factor*blocks(m)%mete3d_1 + (1 - factor)*blocks(m)%mete3d_2

            ! 从气象场中计算时间变化率
            next_time = old_time + create_timedelta(seconds=cfg%dts(m)*j)
            timedelta = next_mete_time - next_time
            factor = timedelta%total_seconds()/cfg%mete_timedelta
            blocks(m)%dzdt = factor*blocks(m)%mete3d_1(:, :, :, blocks(m)%m3d_idx%get('zt')) &
                             + (1 - factor)*blocks(m)%mete3d_2(:, :, :, blocks(m)%m3d_idx%get('zt'))
            blocks(m)%dzdt = (blocks(m)%dzdt - blocks(m)%zt)/cfg%dts(m)
            ! 气象模式在下一时刻给出的密度
            blocks(m)%rho_next = factor*blocks(m)%mete3d_1(:, :, :, blocks(m)%m3d_idx%get('rho')) &
                                 + (1 - factor)*blocks(m)%mete3d_2(:, :, :, blocks(m)%m3d_idx%get('rho'))

            ! 交换风场数据, 大部分气象数据不需要做边界交换
            call fill_halo(proc%tiles(m), blocks(m)%u)  ! nx, ny, nz
            if (proc%tiles(m)%at_north_pole .or. proc%tiles(m)%at_south_pole) then ! 在极点交换的纬向风需要翻转
               call fill_halo(proc%tiles(m), blocks(m)%v, is_v=.false.)
            else
               call fill_halo(proc%tiles(m), blocks(m)%v)
            end if
            call diagnose_meteorology(proc%tiles(m), blocks(m), cfg%dts(m))
            ! 水平平流和扩散需要体积数据进行校正
            call fill_halo(proc%tiles(m), blocks(m)%rho)
            call fill_halo(proc%tiles(m), blocks(m)%volume)

            ! 默认在整点写出过程更新前的当前时刻快照。
            if (old_time%minute == 0 .and. old_time%second == 0 .and. j == 1) then
               filename = old_time%format(get_filename(cfg%out_file_name, domain=cfg%dom_str(m)))
               call write_model_output(proc, proc%domains(m), proc%tiles(m), blocks(m), filename)
            end if

            ! 通过 CCTM 与气象模式的密度差诊断垂直速度。
            ! 当前每个时间步都重新初始化模式密度。
            if (chem_meta%contain("rho")) blocks(m)%rho_cctm = blocks(m)%rho

            if (proc%is_root()) write (*, *) "Start updating concentration"
            ! ======================== 开始更新浓度 ======================== !

            if (proc%is_root()) write (*, *) "update emission"
            ! 添加排放
            do n = 1, blocks(m)%chem_meta%nvar
               if (blocks(m)%chem_meta%vars(n)%read_emission) then
                  ! ug/m^2/s * s/m
                  blocks(m)%chem3d(blocks(m)%ibs:blocks(m)%ibe, blocks(m)%jbs:blocks(m)%jbe, :, n, cfg%twindow) = &
                     blocks(m)%chem3d(blocks(m)%ibs:blocks(m)%ibe, blocks(m)%jbs:blocks(m)%jbe, :, n, cfg%twindow) + &
                     blocks(m)%emis3d(blocks(m)%ibs:blocks(m)%ibe, blocks(m)%jbs:blocks(m)%jbe, :, n)*cfg%dts(m)/ &
                     blocks(m)%dz(blocks(m)%ibs:blocks(m)%ibe, blocks(m)%jbs:blocks(m)%jbe, :)
               end if
            end do

            ! deposition

            ! chemistry

            ! 子区域更新边界条件: iblock%edges(north)%bc = > iblock%chem3d
            call blocks(m)%update_bc(proc%tiles(m), cfg%parent_grid_ratio(m)) ! 更新外部边界条件
            ! 区域边界问题：自由边界(平流) + 体积和密度(平流+扩散) + 风场(平流+扩散)
            call handle_domain_bc(proc%tiles(m), blocks(m)) ! u和v分辨多一个网格，要小心处理

            if (proc%is_root()) write (*, *) "xy advection"
            ! 水平平流过程
            call fill_halo(proc%tiles(m), blocks(m)%chem3d(:, :, :, :, cfg%twindow)) ! 交换污染物浓度
            call drive_hadv_by_ppm(proc%tiles(m), blocks(m), cfg%dts(m))

            if (proc%is_root()) write (*, *) "xy diffusion"
            ! 水平扩散: 需要求浓度梯度（边界交换）
            call fill_halo(proc%tiles(m), blocks(m)%chem3d(:, :, :, :, cfg%twindow)) ! 交换污染物浓度
            call drive_hdiff_by_k_theory(proc%tiles(m), blocks(m), cfg%dts(m))

            if (proc%is_root()) write (*, *) "z diffusion"
            ! 垂直扩散
            call drive_vdiff_by_k_theory(proc%tiles(m), blocks(m), cfg%dts(m))

            if (proc%is_root()) write (*, *) "z advection"
            ! 空气质量模式 和 气象模式的一致性问题。
            if (chem_meta%contain("rho")) call cal_w_by_rho(proc%tiles(m), blocks(m), cfg%nhalo, cfg%dts(m))
            ! 垂直平流最后执行，以统一处理垂直坐标变化引起的浓度变化。
            call drive_vadv_by_ppm(proc%tiles(m), blocks(m), cfg%dts(m))

            ! 同步极点浓度, 需要同步吗？方便水平扩散的计算
            if (proc%domains(m)%is_global) then
               call avg_pole(proc%tiles(m), blocks(m)%chem3d(:, :, :, :, cfg%twindow), proc%domains(m)%nx)
               ! 高纬度滤波，挺难搞的
            end if

            ! 滑动时间窗口, 基本没有必要
            do it = 1, cfg%twindow - 1 ! [..., t-2, t-1, t, t_]
               blocks(m)%chem3d(:, :, :, :, it) = blocks(m)%chem3d(:, :, :, :, it + 1)
            end do

         end do LOOP_INTEGRAL

      end do LOOP_DOM

   end do LOOP_TIME

   call proc%clear()

end program main
