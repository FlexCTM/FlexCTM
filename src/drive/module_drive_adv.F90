module mod_drive_adv
   !! 平流模块
   use mod_const, only: fp, eps
   use mod_block, only: block_type

   use advection, only: cal_cfl_time_step, adv1d_by_ppm
   use parallel, only: tile_type, fill_halo, west, east, south, north

   implicit none

   private
   public drive_hadv_by_ppm, drive_vadv_by_ppm, handle_domain_bc, cal_w_by_rho

contains

   subroutine drive_hadv_by_ppm(tile, iblock, dt)
      !! 水平平流驱动程序
      type(tile_type), intent(in) :: tile       !! 切片信息
      type(block_type), intent(inout) :: iblock !! 数据块
      real(fp), intent(in) :: dt                !! 积分时间

      integer :: nt
      real(fp) :: sdt !! delta time of sub-time step
      real(fp) :: dc(iblock%nx, iblock%ny) !! 浓度变化

      integer :: i, j, k, n, it

      associate (vv => iblock%volume, c => iblock%chem3d, u => iblock%u, v => iblock%v, t => iblock%twindow, &
                 xlen => iblock%mesh%xlen, ylen => iblock%mesh%ylen, dx => iblock%mesh%dx_mean, dy => iblock%mesh%dy_mean)

         do n = 1, iblock%chem_meta%nvar ! 不同污染物
            if (.not. iblock%chem_meta%vars(n)%advected) cycle
            do k = 1, size(v, 3) ! 不同垂直层
               do i = tile%ibs, tile%ibe
                  call cal_cfl_time_step(ylen(i, :), v(i, :, k), dt, sdt, nt) ! y 方向
                  do it = 1, nt ! 确保满足CFL条件
                     call adv1d_by_ppm(sdt, dy(i), v(i, :, k), c(i, :, k, n, t), dc(i, :), volume=vv(i, :, k))
                  end do
               end do
            end do
         end do

         ! 保证一致性
         call fill_halo(tile, c(:, :, :, :, t))

         do n = 1, iblock%chem_meta%nvar ! 不同污染物
            if (.not. iblock%chem_meta%vars(n)%advected) cycle
            do k = 1, size(u, 3) ! 不同垂直层
               do j = tile%jbs, tile%jbe
                  ! 根据各高度和方向的风速确定稳定时间步长。
                  call cal_cfl_time_step(xlen(:, j), u(:, j, k), dt, sdt, nt)
                  do it = 1, nt ! 确保满足CFL条件
                     call adv1d_by_ppm(sdt, dx(j), u(:, j, k), c(:, j, k, n, t), dc(:, j), volume=vv(:, j, k))
                  end do
               end do
            end do
         end do

      end associate

   end subroutine drive_hadv_by_ppm

   subroutine handle_domain_bc(tile, iblock)
      !! 将区域边界处理为自由边界
      type(tile_type), intent(in) :: tile     !! 切片信息
      type(block_type), intent(inout) :: iblock   !! 数据块

      integer :: i, j, k, n

      associate (c => iblock%chem3d, u => iblock%u, v => iblock%v, t => iblock%twindow, vv => iblock%volume, rho => iblock%rho)
         do n = 1, iblock%chem_meta%nvar ! 不同污染物
            if (.not. iblock%chem_meta%vars(n)%advected) cycle
            do k = 1, size(u, 3) ! 不同垂直层
               if (tile%ngbs(west)%is_domain_edge()) then
                  do j = 1, iblock%ny
                     vv(iblock%iws:iblock%iwe, j, k) = vv(iblock%ibs, j, k)
                     rho(iblock%iws:iblock%iwe, j, k) = rho(iblock%ibs, j, k)
                     if (u(iblock%iwe, j, k) < 0) c(iblock%iws:iblock%iwe, j, k, n, t) = c(iblock%ibs, j, k, n, t)
                     u(iblock%iws:iblock%iwe - 1, j, k) = u(iblock%iwe, j, k) ! WRF 交错网格需要在区域边界外推风速。
                     v(iblock%iws:iblock%iwe, j, k) = v(iblock%ibs, j, k)
                  end do
               end if
               if (tile%ngbs(east)%is_domain_edge()) then
                  do j = 1, iblock%ny
                     vv(iblock%ies:iblock%iee, j, k) = vv(iblock%ibe, j, k)
                     rho(iblock%ies:iblock%iee, j, k) = rho(iblock%ibe, j, k)
                     if (u(iblock%ibe, j, k) > 0) c(iblock%ies:iblock%iee, j, k, n, t) = c(iblock%ibe, j, k, n, t)
                     u(iblock%ies:iblock%iee, j, k) = u(iblock%ibe, j, k)
                     v(iblock%ies:iblock%iee, j, k) = v(iblock%ibe, j, k)
                  end do
               end if
               if (tile%ngbs(south)%is_domain_edge()) then
                  do i = 1, iblock%nx
                     vv(i, iblock%jss:iblock%jse, k) = vv(i, iblock%jbs, k)
                     rho(i, iblock%jss:iblock%jse, k) = rho(i, iblock%jbs, k)
                     if (v(i, iblock%jse, k) < 0) c(i, iblock%jss:iblock%jse, k, n, t) = c(i, iblock%jbs, k, n, t)
                     u(i, iblock%jss:iblock%jse, k) = u(i, iblock%jbs, k)
                     v(i, iblock%jss:iblock%jse - 1, k) = v(i, iblock%jse, k) ! WRF 交错网格的边界外推。
                  end do
               end if
               if (tile%ngbs(north)%is_domain_edge()) then
                  do i = 1, iblock%nx
                     vv(i, iblock%jns:iblock%jne, k) = vv(i, iblock%jbe, k)
                     rho(i, iblock%jns:iblock%jne, k) = rho(i, iblock%jbe, k)
                     if (v(i, iblock%jbe, k) > 0) c(i, iblock%jns:iblock%jne, k, n, t) = c(i, iblock%jbe, k, n, t)
                     u(i, iblock%jns:iblock%jne, k) = u(i, iblock%jbe, k)
                     v(i, iblock%jns:iblock%jne, k) = v(i, iblock%jbe, k)
                  end do
               end if
            end do
         end do
      end associate
   end subroutine handle_domain_bc

   subroutine drive_vadv_by_ppm(tile, iblock, dt)
      !! 垂直平流模块驱动程序
      type(tile_type), intent(in) :: tile       !! 切片信息
      type(block_type), intent(inout) :: iblock !! 数据块
      real(fp), intent(in) :: dt                !! 积分时间

      integer :: nt
      real(fp) :: sdt !! delta time of sub-time step
      real(fp) :: dc(iblock%nz) !! 浓度变化 delta C
      real(fp) :: dc_by_dh(iblock%nz) !! 网格高度变化引起的浓度变化 delta C
      real(fp) :: mass, mass_new !! 总质量
      real(fp) :: dz_next(iblock%nz) !! 下一时刻的网格垂直厚度；当前对不同变量存在重复计算。
      integer :: i, j, k, n, it

      associate (vv => iblock%volume, c => iblock%chem3d, w => iblock%w, t => iblock%twindow, dz => iblock%dz, dzdt => iblock%dzdt)
         do n = 1, iblock%chem_meta%nvar ! 不同污染物
            if (.not. iblock%chem_meta%vars(n)%advected) cycle
            if (iblock%chem_meta%vars(n)%name /= 'rho') then
               do j = tile%jbs, tile%jbe
                  do i = tile%ibs, tile%ibe
                     mass = sum(c(i, j, :, n, t)*dz(i, j, :))
                     ! 网格高度随时间变化
                     do k = 1, iblock%nz
                        if (k == 1) then
                           dz_next(k) = dz(i, j, k) + dzdt(i, j, k)*dt
                           dc_by_dh(k) = -c(i, j, k, n, t)*dzdt(i, j, k)/dz(i, j, k)
                        else
                           dz_next(k) = dz(i, j, k) + (dzdt(i, j, k) - dzdt(i, j, k - 1))*dt
                           dc_by_dh(k) = -c(i, j, k, n, t)*(dzdt(i, j, k) - dzdt(i, j, k - 1))/dz(i, j, k)
                        end if
                     end do
                     if (n == 1) w(i, j, :) = w(i, j, :) - dzdt(i, j, :) ! terrain-following absolute height 坐标
                     ! 垂直分辨率很小（垂直风速通常也较小）。
                     call cal_cfl_time_step(dz(i, j, :), w(i, j, :), dt, sdt, nt)
                     do it = 1, nt ! 确保满足CFL条件
                        ! 平流项 dz在时间迭代前后, 会发生变化 (dzdt导致的dz变化), 会导致质量不守恒
                        call adv1d_by_ppm(sdt, dz(i, j, :), w(i, j, :), c(i, j, :, n, t), dc)
                     end do
                     do k = 1, iblock%nz ! 质量不守恒，没法保证正负问题
                        c(i, j, k, n, t) = c(i, j, k, n, t) - dc_by_dh(k)
                        if (c(i, j, k, n, t) < eps) c(i, j, k, n, t) = 0._fp
                     end do
                     ! 质量守恒
                     mass_new = sum(c(i, j, :, n, t)*dz_next)
                     if (mass_new > 0) c(i, j, :, n, t) = c(i, j, :, n, t)*mass/mass_new
                  end do
               end do
            end if
         end do
      end associate

   end subroutine drive_vadv_by_ppm

   subroutine cal_w_by_rho(tile, iblock, nhalo, dt)
      !! 通过气象模式给的密度的时间变化求解垂直速度
      type(tile_type), intent(in) :: tile       !! 切片信息
      type(block_type), intent(inout) :: iblock !! 数据块
      integer, intent(in) :: nhalo              !! 并行交换宽度
      real(fp), intent(in) :: dt                !! 积分时间

      real(fp) :: rho  !! 顶边的平均密度
      real(fp) :: rhow !! rho*w
      real(fp) :: rhod !! 密度差
      real(fp) :: v(iblock%nz) !! 垂直风速
      integer :: i, j, k
      integer :: jbs, jbe, ibs, ibe

      ! 区域模拟的案例中，cctm计算的密度与气象模式计算的相差太大了
      jbs = tile%jbs
      jbe = tile%jbe
      ibs = tile%ibs
      ibe = tile%ibe
      if (tile%ngbs(west)%is_domain_edge()) ibs = ibs + nhalo
      if (tile%ngbs(east)%is_domain_edge()) ibe = ibe - nhalo
      if (tile%ngbs(south)%is_domain_edge()) jbs = jbs + nhalo
      if (tile%ngbs(north)%is_domain_edge()) jbe = jbe - nhalo

      v(iblock%nz) = 0._fp ! 假设最顶层没有输送
      associate (rho_mete => iblock%rho_next, rho_cctm => iblock%rho_cctm, w => iblock%w, dz => iblock%dz)
         do j = jbs, jbe
            do i = ibs, ibe
               rhow = 0._fp ! 最底层风速为 0
               do k = 1, iblock%nz - 1 ! 求积分
                  rho = (rho_mete(i, j, k)*dz(i, j, k + 1) + rho_mete(i, j, k + 1)*dz(i, j, k))/ (dz(i, j, k + 1) + dz(i, j, k))
                  rhow = rhow - ((rho_mete(i, j, k) - rho_cctm(i, j, k))/dt)*dz(i, j, k)
                  v(k) = rhow/rho ! rho*w = rhow, 注意等式左右两边的rho含义一样
               end do
               w(i, j, :) = v
            end do
         end do
      end associate
   end subroutine cal_w_by_rho

end module mod_drive_adv
