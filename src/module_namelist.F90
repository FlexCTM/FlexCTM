module mod_namelist
  !! 全局配置参数
   use mod_const, only: fp
   use mod_error, only: fatal_error

   implicit none

   private

   public :: config_type, load_config, calculate_time_steps, calculate_interval_steps

   integer, parameter :: lcc = 1
   integer, parameter :: latlon = 0
   integer, parameter :: MAX_DOM = 8

   type :: config_type
      integer :: ndom                 !! Number of configured domains. / 配置的区域数。
      integer :: nlev                 !! Number of vertical mass layers. / 垂直质量层数。
      integer :: we(MAX_DOM)          !! Valid X-cell count per domain. / 各区域 X 方向有效格点数。
      integer :: sn(MAX_DOM)          !! Valid Y-cell count per domain. / 各区域 Y 方向有效格点数。
      integer :: parent_id(MAX_DOM)   !! One-based parent-domain index; root uses 0. / 父区域一基下标，根区域为 0。
      integer :: i_parent_start(MAX_DOM) !! Child southwest X index in parent. / 子区域西南角在父区域的 X 下标。
      integer :: j_parent_start(MAX_DOM) !! Child southwest Y index in parent. / 子区域西南角在父区域的 Y 下标。
      integer :: parent_grid_ratio(MAX_DOM) !! Child/parent resolution ratio. / 子父网格分辨率比。
      integer :: proj_id              !! Projection code: 0 latlon, 1 LCC. / 投影编号：0 经纬度，1 LCC。
      integer :: twindow              !! Chemistry time levels retained in memory. / 内存中保留的化学时间层数。
      integer :: nhalo                !! Horizontal halo width [cells]. / 水平 halo 宽度 [格点]。
      integer :: emis_nlev            !! Vertical levels present in emission files. / 排放文件的垂直层数。
      integer :: nt                   !! Number of root-domain time steps. / 根区域总时间步数。
      integer :: nts(MAX_DOM)         !! Substeps per root step for each domain. / 各区域每个根时间步的子步数。
      integer :: mete_steps           !! Root steps between meteorology inputs. / 相邻气象时次间的根时间步数。
      integer :: output_steps         !! Root steps between model outputs. / 相邻模式输出间的根时间步数。
      real(fp) :: delta               !! Root-domain horizontal spacing [degree or m]. / 根区域水平分辨率 [度或米]。
      real(fp) :: xorg, yorg          !! Root southwest origin [degree or m]. / 根区域西南角坐标 [度或米]。
      real(fp) :: ref_lat, ref_lon    !! Projection origin [degree]. / 投影原点纬度和经度 [度]。
      real(fp) :: truelat1, truelat2  !! LCC standard parallels [degree]. / LCC 第一、第二标准纬线 [度]。
      real(fp) :: dt                  !! Root-domain integration step [s]. / 根区域积分时间步长 [s]。
      real(fp) :: mete_timedelta      !! Meteorology input interval [s]. / 气象输入时间间隔 [s]。
      real(fp) :: output_timedelta    !! Model output interval [s]. / 模式输出时间间隔 [s]。
      real(fp) :: run_minutes(MAX_DOM) !! Requested duration component [min]. / 配置的运行分钟分量。
      real(fp) :: run_hours(MAX_DOM)  !! Requested duration component [h]. / 配置的运行小时分量。
      real(fp) :: run_days(MAX_DOM)   !! Requested duration component [day]. / 配置的运行天数分量。
      real(fp) :: deltas(MAX_DOM)     !! Derived spacing per domain [degree or m]. / 各区域派生分辨率 [度或米]。
      real(fp) :: xorgs(MAX_DOM), yorgs(MAX_DOM) !! Derived southwest origins. / 各区域派生西南角坐标。
      real(fp) :: dts(MAX_DOM)        !! Derived integration step per domain [s]. / 各区域派生积分步长 [s]。
      logical :: is_global            !! Root domain has global/polar topology. / 根区域是否使用全球及极点拓扑。
      logical :: restart              !! Restart-mode request flag. / 是否请求热启动。
      character(len=16) :: start_time !! Start timestamp in YYYYMMDDHH form. / YYYYMMDDHH 格式的起始时间。
      character(len=256) :: chem_meta_file !! Chemical metadata path. / 化学变量元数据路径。
      character(len=256) :: mete_table_file !! FlexCTM 标准气象变量表路径。
      character(len=256) :: mete_mapping_file !! 数据集气象接口映射表路径。
      character(len=16) :: mete_source !! Meteorology source: wrf or mock. / 气象数据源。
      character(len=256) :: ic_file, bc_file !! Initial/boundary filename templates. / 初值与边界文件名模板。
      character(len=256) :: emis_file, mete_file !! Emission/meteorology templates. / 排放与气象文件名模板。
      character(len=256) :: out_file      !! Output filename template. / 输出文件名模板。
      character(len=256) :: static_grid_file !! 静态网格输出模板。
      character(len=1) :: dom_str(MAX_DOM) !! One-character domain labels. / 用于文件名替换的单字符区域标识。
   end type config_type
   ! 网格参数
   integer :: ndom = 0, nlev = 0
   integer :: we(MAX_DOM) = 0, sn(MAX_DOM) = 0, parent_id(MAX_DOM) = 0
   integer :: i_parent_start(MAX_DOM) = 1, j_parent_start(MAX_DOM) = 1
   integer :: parent_grid_ratio(MAX_DOM) = 1

   real(fp) :: delta = 0.0_fp
   integer :: proj_id = latlon  !! 0 for latlon, 1 for lcc
   real(fp) :: xorg = -180.0_fp
   real(fp) :: yorg = -90.0_fp

   real(fp) :: ref_lat = 28.5_fp
   real(fp) :: ref_lon = 114.0_fp
   real(fp) :: truelat1 = 15.0_fp
   real(fp) :: truelat2 = 40.0_fp

   logical :: is_global = .true. !! 是否为全球区域模拟

   ! 物理方案配置
   integer :: twindow = 1  !! 保留的时间层数
   integer :: nhalo = 3  !! 平流和扩散所需的最大 halo 宽度

   character(len=16) :: start_time = ''
   real(fp) :: run_minutes(MAX_DOM) = 0.0_fp !! 积分时长（分钟）
   real(fp) :: run_hours(MAX_DOM) = 0.0_fp   !! 积分时长（小时）
   real(fp) :: run_days(MAX_DOM) = 0.0_fp    !! 积分时长（天）
   real(fp) :: dt = 900.0_fp

   logical :: restart = .false. !! 是否为热启动

   character(len=256) :: chem_meta_file = ''
   character(len=256) :: mete_table_file = ''
   character(len=256) :: mete_mapping_file = ''
   character(len=16) :: mete_source = 'wrf'
   character(len=256) :: ic_file = ''
   character(len=256) :: bc_file = ''

   integer :: emis_nlev = 20 !! 排放数据的垂直层数
   character(len=256) :: emis_file = ''
   real(fp) :: mete_timedelta = 3600.0_fp
   character(len=256) :: mete_file = ''

   character(len=256) :: out_file = 'naqp_d0[DOMAIN]_%Y%m%d%H.nc'
   real(fp) :: output_timedelta = 3600.0_fp
   character(len=256) :: static_grid_file = 'static_meta_d0[DOMAIN].nc'

   character(len=1) :: dom_str(MAX_DOM)
   real(fp) :: deltas(MAX_DOM)   !! 各个区域的分辨率
   real(fp) :: xorgs(MAX_DOM)    !! 各个区域的左下角起点
   real(fp) :: yorgs(MAX_DOM)    !! 各个区域的左下角起点
   real(fp) :: dts(MAX_DOM)      !! 各个区域的积分间隔
   integer :: nts(MAX_DOM)      !! 每个全局时间步内各区域的子步数
   integer :: nt      !! 全局时间迭代次数
   integer :: mete_steps, output_steps, hourly_steps

   namelist /region/ ndom, nlev, we, sn, parent_id, parent_grid_ratio, i_parent_start, j_parent_start
   namelist /proj/ is_global, proj_id, xorg, yorg, ref_lat, ref_lon, truelat1, truelat2, delta
   namelist /time/ start_time, run_minutes, run_hours, run_days, dt, restart
   namelist /physics/ twindow, nhalo
   namelist /chem/ chem_meta_file, ic_file, bc_file, emis_file, emis_nlev
   namelist /mete/ mete_table_file, mete_mapping_file, mete_source, mete_file, mete_timedelta
   namelist /output/ out_file, output_timedelta, static_grid_file

contains

   function load_config(filename) result(config)
      character(len=*), optional, intent(in) :: filename !! 显式配置路径；应用层默认读取命令行。
      type(config_type) :: config

      call parse_namelist(filename)
      config%ndom = ndom; config%nlev = nlev
      config%we = we; config%sn = sn; config%parent_id = parent_id
      config%i_parent_start = i_parent_start; config%j_parent_start = j_parent_start
      config%parent_grid_ratio = parent_grid_ratio
      config%proj_id = proj_id; config%delta = delta; config%xorg = xorg; config%yorg = yorg
      config%ref_lat = ref_lat; config%ref_lon = ref_lon
      config%truelat1 = truelat1; config%truelat2 = truelat2; config%is_global = is_global
      config%twindow = twindow; config%nhalo = nhalo
      config%start_time = start_time; config%run_minutes = run_minutes
      config%run_hours = run_hours; config%run_days = run_days; config%dt = dt
      config%restart = restart; config%chem_meta_file = chem_meta_file
      config%mete_table_file = mete_table_file; config%mete_mapping_file = mete_mapping_file
      config%mete_source = mete_source
      config%ic_file = ic_file; config%bc_file = bc_file
      config%emis_nlev = emis_nlev; config%emis_file = emis_file
      config%mete_timedelta = mete_timedelta; config%mete_file = mete_file
      config%out_file = out_file; config%output_timedelta = output_timedelta
      config%static_grid_file = static_grid_file
      config%dom_str = dom_str; config%deltas = deltas; config%xorgs = xorgs
      config%yorgs = yorgs; config%dts = dts; config%nts = nts; config%nt = nt
      config%mete_steps = mete_steps; config%output_steps = output_steps
   end function load_config

   subroutine parse_namelist(filename)
    !! 按固定分组顺序解析并验证配置文件。
      character(len=*), optional, intent(in) :: filename
      character(256) :: namelist_path
      character(512) :: iomsg

      integer :: i, unit, iostat

      if (present(filename)) then
         namelist_path = filename
      else
         call get_command_argument(1, namelist_path)
      end if
      if (namelist_path == '') then
         call fatal_error('a namelist file path is required as the first command-line argument')
      end if

      open (newunit=unit, file=trim(namelist_path), status='old', action='read', iostat=iostat, iomsg=iomsg)
      if (iostat /= 0) call fatal_error('cannot open namelist file "'//trim(namelist_path)//'": '//trim(iomsg))
      read (unit, nml=region, iostat=iostat, iomsg=iomsg)
      if (iostat /= 0) call fatal_error('cannot read &region from "'//trim(namelist_path)//'": '//trim(iomsg))
      read (unit, nml=proj, iostat=iostat, iomsg=iomsg)
      if (iostat /= 0) call fatal_error('cannot read &proj from "'//trim(namelist_path)//'": '//trim(iomsg))
      read (unit, nml=time, iostat=iostat, iomsg=iomsg)
      if (iostat /= 0) call fatal_error('cannot read &time from "'//trim(namelist_path)//'": '//trim(iomsg))
      read (unit, nml=physics, iostat=iostat, iomsg=iomsg)
      if (iostat /= 0) call fatal_error('cannot read &physics from "'//trim(namelist_path)//'": '//trim(iomsg))
      read (unit, nml=chem, iostat=iostat, iomsg=iomsg)
      if (iostat /= 0) call fatal_error('cannot read &chem from "'//trim(namelist_path)//'": '//trim(iomsg))
      read (unit, nml=mete, iostat=iostat, iomsg=iomsg)
      if (iostat /= 0) call fatal_error('cannot read &mete from "'//trim(namelist_path)//'": '//trim(iomsg))
      read (unit, nml=output, iostat=iostat, iomsg=iomsg)
      if (iostat /= 0) call fatal_error('cannot read &output from "'//trim(namelist_path)//'": '//trim(iomsg))
      close (unit, iostat=iostat, iomsg=iomsg)
      if (iostat /= 0) call fatal_error('cannot close namelist file "'//trim(namelist_path)//'": '//trim(iomsg))

      if (ndom < 1 .or. ndom > MAX_DOM) call fatal_error('ndom must be between 1 and 8')
      if (nlev < 1) call fatal_error('nlev must be positive')
      if (any(we(:ndom) < 1) .or. any(sn(:ndom) < 1)) call fatal_error('all configured horizontal grid sizes must be positive')
      if (delta <= 0.0_fp) call fatal_error('grid spacing delta must be positive')
      if (proj_id /= latlon .and. proj_id /= lcc) call fatal_error('proj_id must be 0 (latlon) or 1 (LCC)')
      if (len_trim(start_time) == 0) call fatal_error('start_time must be configured')
      if (len_trim(chem_meta_file) == 0 .or. len_trim(mete_table_file) == 0) &
         call fatal_error('chemical metadata and meteorology table paths must be configured')
      if (trim(mete_source) /= 'wrf' .and. trim(mete_source) /= 'mock') call fatal_error('mete_source must be "wrf" or "mock"')
      if (trim(mete_source) == 'wrf' .and. len_trim(mete_mapping_file) == 0) &
         call fatal_error('WRF meteorology requires mete_mapping_file')
      if (nhalo < 1 .or. twindow < 1) call fatal_error('nhalo and twindow must be positive')
      if (emis_nlev < 1 .or. emis_nlev > nlev) call fatal_error('emis_nlev must be between 1 and nlev')
      do i = 2, ndom
         if (parent_id(i) < 1 .or. parent_id(i) >= i) call fatal_error('each nested domain must reference an earlier parent domain')
         if (parent_grid_ratio(i) < 1) call fatal_error('parent_grid_ratio must be positive')
      end do

      if (proj_id == 1) is_global = .false.

      ! 计算不同区域的参数
      if (proj_id == latlon) then
         xorgs(1) = xorg
         yorgs(1) = yorg
      else
         xorgs(1) = -we(1)*delta/2
         yorgs(1) = -sn(1)*delta/2
      end if
      deltas(1) = delta

      run_minutes(1) = (run_days(1)*24.0_fp + run_hours(1))*60.0_fp + run_minutes(1)
      call calculate_time_steps(run_minutes(1), dt, nt, iostat, iomsg)
      if (iostat /= 0) call fatal_error(trim(iomsg))
      call calculate_interval_steps(mete_timedelta, dt, 'mete_timedelta', mete_steps, iostat, iomsg)
      if (iostat /= 0) call fatal_error(trim(iomsg))
      call calculate_interval_steps(output_timedelta, dt, 'output_timedelta', output_steps, iostat, iomsg)
      if (iostat /= 0) call fatal_error(trim(iomsg))
      call calculate_interval_steps(3600._fp, dt, 'hourly boundary and emission interval', hourly_steps, iostat, iomsg)
      if (iostat /= 0) call fatal_error(trim(iomsg))

      nts(1) = 1
      dts(1) = dt

      do i = 1, ndom
         write (dom_str(i), '(I1)') i
         if (i > 1) then
            deltas(i) = deltas(parent_id(i))/parent_grid_ratio(i)
            xorgs(i) = xorgs(parent_id(i)) + deltas(parent_id(i))*(i_parent_start(i) - 1)
            yorgs(i) = yorgs(parent_id(i)) + deltas(parent_id(i))*(j_parent_start(i) - 1)

            nts(i) = nts(parent_id(i))*parent_grid_ratio(i)
            dts(i) = dts(parent_id(i))/parent_grid_ratio(i)
         end if
      end do
   end subroutine parse_namelist

   subroutine calculate_time_steps(total_minutes, step_seconds, steps, stat, errmsg)
      !! 总时长必须是时间步长的整数倍，避免静默截断结束时间。
      real(fp), intent(in) :: total_minutes, step_seconds
      integer, intent(out) :: steps, stat
      character(len=*), intent(out) :: errmsg

      real(fp) :: exact_steps, tolerance

      steps = 0
      stat = 0
      errmsg = ''
      if (total_minutes < 0.0_fp) then
         stat = 1
         errmsg = 'run duration must not be negative'
         return
      end if
      if (step_seconds <= 0.0_fp) then
         stat = 1
         errmsg = 'time step dt must be positive'
         return
      end if

      exact_steps = total_minutes*60.0_fp/step_seconds
      steps = nint(exact_steps)
      tolerance = 100.0_fp*epsilon(1.0_fp)*max(1.0_fp, abs(exact_steps))
      if (abs(exact_steps - real(steps, fp)) > tolerance) then
         stat = 1
         steps = 0
         errmsg = 'run duration must be an integer multiple of dt'
      end if
   end subroutine calculate_time_steps

   subroutine calculate_interval_steps(interval_seconds, step_seconds, name, steps, stat, errmsg)
      !! 将输入或输出间隔转换为整数个根时间步。
      real(fp), intent(in) :: interval_seconds, step_seconds
      character(len=*), intent(in) :: name
      integer, intent(out) :: steps, stat
      character(len=*), intent(out) :: errmsg

      real(fp) :: exact_steps, tolerance

      steps = 0
      stat = 0
      errmsg = ''
      if (interval_seconds <= 0._fp) then
         stat = 1
         errmsg = trim(name)//' must be positive'
         return
      end if
      if (step_seconds <= 0._fp) then
         stat = 1
         errmsg = 'time step dt must be positive'
         return
      end if

      exact_steps = interval_seconds/step_seconds
      steps = nint(exact_steps)
      tolerance = 100._fp*epsilon(1._fp)*max(1._fp, abs(exact_steps))
      if (abs(exact_steps - real(steps, fp)) > tolerance) then
         stat = 1
         steps = 0
         errmsg = trim(name)//' must be an integer multiple of dt'
      end if
   end subroutine calculate_interval_steps

end module mod_namelist
