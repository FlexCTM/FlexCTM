module mod_block
   !! 当前进程执行时间积分所需的全部数据。

   use mod_const, only: fp
   use mod_mesh, only: mesh_type
   use mod_chem_type, only: chem_table_type
   use mod_mete_type, only: mete_table_type

   use parallel, only: tile_type, bridge_type, west, east, south, north
   use container, only: string_hash_map

   implicit none

   private

   public block_type

   type edge_type
      logical :: is_edge = .false. !! 是否为区域边界
      integer :: nx !! x方向网格数
      integer :: ny !! y方向网格数
      real(fp), allocatable :: bc(:, :, :, :) !! nx, ny, nz, n_chem_var

   end type edge_type

   type block_type
      type(mesh_type) :: mesh !! 该进程的二维网格信息
      ! 网格信息
      real(fp) :: xorg !! Local southwest X origin including halo [degree or m]. / 包含 halo 的局地西南角 X 坐标。
      real(fp) :: yorg !! Local southwest Y origin including halo [degree or m]. / 包含 halo 的局地西南角 Y 坐标。

      integer :: nx !! Allocated X size including halo. / 包含 halo 的 X 方向分配尺寸。
      integer :: ny !! Allocated Y size including halo. / 包含 halo 的 Y 方向分配尺寸。
      integer :: nz !! Vertical mass-layer count; no vertical halo. / 垂直质量层数，不含垂直 halo。
      ! 去掉一圈halo: block中的有效数据
      integer :: ibs !! x方向开始位置: I index of Block Start
      integer :: ibe !! x方向结束位置: I index of Block End
      integer :: jbs !! y方向开始位置
      integer :: jbe !! y方向结束位置
      ! halo相关索引
      integer :: iws !! 西部边界开始
      integer :: iwe !! 西部边界结束
      integer :: ies !! 东部边界开始
      integer :: iee !! 东部边界结束
      integer :: jss !! 南部边界开始
      integer :: jse !! 南部边界结束
      integer :: jns !! 北部边界开始
      integer :: jne !! 北部边界结束

      type(chem_table_type) chem_meta !! 元数据信息
      integer :: twindow        !! 保留时间窗口
      real(fp), allocatable :: chem3d(:, :, :, :, :) !! 污染变量 nx, ny, nz, n_chem_var, twindow, ug/m3
      type(edge_type) :: edges(4)        !! 子切片中包含的区域边界
      type(edge_type) :: coarse_edges(4) !! 从父区域接收的边界

      real(fp), allocatable :: emis3d(:, :, :, :)    !! 排放变量 nx, ny, nz, n_emis_var, ug/m3

      type(mete_table_type) mete_table !! 标准气象变量及公共诊断变量表。
      ! 气象数据需要时间插值；交错风速采用每个质量网格的右侧边界值。

      ! 'kx', 'ky', 'kz' 等变量在计算时更新
      type(string_hash_map) :: m3d_idx  !! 3d气象变量索引
      real(fp), allocatable :: mete3d(:, :, :, :) !! 时间插值后的气象变量 nx, ny, nz, n_mete_var
      real(fp), allocatable :: mete3d_1(:, :, :, :)  !! 积分时刻之前的相邻气象数据
      real(fp), allocatable :: mete3d_2(:, :, :, :)  !! 积分时刻之后的相邻气象数据

      type(string_hash_map) :: m2d_idx !! 2d气象变量索引
      real(fp), allocatable :: mete2d(:, :, :)    !! 时间插值后的气象变量 nx, ny, nz, n_mete_var
      real(fp), allocatable :: mete2d_1(:, :, :)  !! 积分时刻之前的相邻气象数据
      real(fp), allocatable :: mete2d_2(:, :, :)  !! 积分时刻之后的相邻气象数据

      ! 常用气象变量的指针别名，便于后续取值。
      real(fp), pointer :: u(:, :, :)      !! 风速 m/s
      real(fp), pointer :: v(:, :, :)      !! 风速 m/s
      real(fp), pointer :: w(:, :, :)      !! 风速 m/s
      real(fp), pointer :: dz(:, :, :)     !! 网格的高度 m
      real(fp), pointer :: zt(:, :, :)     !! 网格顶部高度 m
      real(fp), pointer :: dzdt(:, :, :)   !! 网格顶部高度的时间变率 m/s

      real(fp), pointer :: rho(:, :, :)    !! 气象数据中的干空气密度 kg/m3
      real(fp), allocatable :: rho_next(:, :, :) !! 下一气象时次插值后的干空气密度 kg/m3。
      real(fp), pointer :: rho_cctm(:, :, :) !! cctm的动力过程更新的干空气密度 kg/m3

      real(fp), pointer :: volume(:, :, :) !! 网格的体积 m3

      real(fp), pointer :: T(:, :, :)       !! 温度 K
      real(fp), pointer :: thetav(:, :, :)  !! 虚位温 K
      real(fp), pointer :: TSK(:, :)        !! 地表温度 K

      real(fp), pointer :: P(:, :, :)   !! 空气压强 Pa
      real(fp), pointer :: PSFC(:, :)   !! 地表空气压强 Pa

      ! 边界层相关变量
      real(fp), pointer :: PBL(:, :)    !! 边界层高度 m
      real(fp), pointer :: Ri(:, :)     !! bulk Richardson number
      real(fp), pointer :: RMOL(:, :)   !! 1./Monin Ob. Length
      real(fp), pointer :: ustar(:, :)  !! friction velocity. (m/s)
      real(fp), pointer :: wstar(:, :)  !! convective velocity (m/s)
      ! 交错网格上的扩散系数
      real(fp), pointer :: kx(:, :, :) !! horizontal diffusion coefficient in x (m2/s)
      real(fp), pointer :: ky(:, :, :) !! horizontal diffusion coefficient in y (m2/s)
      real(fp), pointer :: kz(:, :, :) !! vertical diffusion coefficient in z (m2/s)

      ! 静态数据
      real(fp), allocatable :: terrain(:, :)     !! 地形高度 m

   contains
      procedure :: init => block_init    !! 初始化数据
      procedure :: clear => block_clear  !! 释放数组
      procedure :: update_bc => block_update_bc  !! 更新边界条件

      final :: block_final
   end type block_type

contains

   subroutine block_init(this, bridge, tile, nz, nhalo, chem_meta, mete_table, twindow)
      !! 初始化数据结构
      class(block_type), target, intent(inout) :: this
      type(bridge_type), intent(in) :: bridge !! 子区域和父区域的连接
      type(tile_type), intent(in) :: tile   !! 切片信息
      integer, intent(in) :: nz    !! 垂直层数
      integer, intent(in) :: nhalo !! halo宽度
      type(chem_table_type), intent(in) :: chem_meta !! 化学物种头信息
      type(mete_table_type), intent(in) :: mete_table !! 气象变量定义表。
      integer, intent(in) :: twindow !! 时间窗口

      integer :: n

      this%twindow = twindow
      this%chem_meta = chem_meta
      this%mete_table = mete_table

      this%ibs = tile%ibs
      this%ibe = tile%ibe
      this%jbs = tile%jbs
      this%jbe = tile%jbe

      this%iws = 1
      this%iwe = nhalo
      this%ies = nhalo + tile%nx + 1
      this%iee = nhalo + tile%nx + nhalo
      this%jss = 1
      this%jse = nhalo
      this%jns = nhalo + tile%ny + 1
      this%jne = nhalo + tile%ny + nhalo

      this%nz = nz
      this%ny = tile%ny + 2*nhalo
      this%nx = tile%nx + 2*nhalo

      if (bridge%parent_id > 0) then ! 子区域需要从父区域提取边界。
         this%coarse_edges(west)%nx = bridge%wnx
         this%coarse_edges(west)%ny = bridge%wny
         this%coarse_edges(east)%nx = bridge%enx
         this%coarse_edges(east)%ny = bridge%eny
         this%coarse_edges(south)%nx = bridge%snx
         this%coarse_edges(south)%ny = bridge%sny
         this%coarse_edges(north)%nx = bridge%nnx
         this%coarse_edges(north)%ny = bridge%nny
         allocate (this%coarse_edges(west)%bc(bridge%wnx, bridge%wny, nz, chem_meta%nvar))
         allocate (this%coarse_edges(east)%bc(bridge%enx, bridge%eny, nz, chem_meta%nvar))
         allocate (this%coarse_edges(south)%bc(bridge%snx, bridge%sny, nz, chem_meta%nvar))
         allocate (this%coarse_edges(north)%bc(bridge%nnx, bridge%nny, nz, chem_meta%nvar))
      end if

      if (tile%ngbs(west)%is_domain_edge()) then
         this%edges(west)%nx = nhalo
         this%edges(west)%ny = tile%ny
         this%edges(west)%is_edge = .true.
         allocate (this%edges(west)%bc(nhalo, tile%ny, nz, chem_meta%nvar))
      end if
      if (tile%ngbs(east)%is_domain_edge()) then
         this%edges(east)%nx = nhalo
         this%edges(east)%ny = tile%ny
         this%edges(east)%is_edge = .true.
         allocate (this%edges(east)%bc(nhalo, tile%ny, nz, chem_meta%nvar))
      end if
      if (tile%ngbs(south)%is_domain_edge()) then
         this%edges(south)%nx = tile%nx
         this%edges(south)%ny = nhalo
         this%edges(south)%is_edge = .true.
         allocate (this%edges(south)%bc(tile%nx, nhalo, nz, chem_meta%nvar))
      end if
      if (tile%ngbs(north)%is_domain_edge()) then
         this%edges(north)%nx = tile%nx
         this%edges(north)%ny = nhalo
         this%edges(north)%is_edge = .true.
         allocate (this%edges(north)%bc(tile%nx, nhalo, nz, chem_meta%nvar))
      end if

      allocate (this%chem3d(this%nx, this%ny, nz, chem_meta%nvar, twindow))
      allocate (this%emis3d(this%nx, this%ny, nz, chem_meta%nvar))

      if (chem_meta%contain("rho")) then
         this%rho_cctm => this%chem3d(:, :, :, chem_meta%idx("rho"), twindow)
      end if

      ! 静态数据
      allocate (this%terrain(this%nx, this%ny))

      ! 气象变量
      allocate (this%mete2d(this%nx, this%ny, mete_table%n_2d), source=0._fp)
      allocate (this%mete2d_1(this%nx, this%ny, mete_table%n_2d), source=0._fp)
      allocate (this%mete2d_2(this%nx, this%ny, mete_table%n_2d), source=0._fp)

      allocate (this%mete3d(this%nx, this%ny, nz, mete_table%n_3d), source=0._fp)
      allocate (this%mete3d_1(this%nx, this%ny, nz, mete_table%n_3d), source=0._fp)
      allocate (this%mete3d_2(this%nx, this%ny, nz, mete_table%n_3d), source=0._fp)
      allocate (this%rho_next(this%nx, this%ny, nz), source=0._fp)

      ! 初始化索引
      do n = 1, mete_table%n_3d
         call this%m3d_idx%set(mete_table%var3ds(n)%name, n)
      end do

      do n = 1, mete_table%n_2d
         call this%m2d_idx%set(mete_table%var2ds(n)%name, n)
      end do

      this%u => this%mete3d(:, :, :, this%m3d_idx%get('U'))
      this%v => this%mete3d(:, :, :, this%m3d_idx%get('V'))
      this%w => this%mete3d(:, :, :, this%m3d_idx%get('W'))
      this%dz => this%mete3d(:, :, :, this%m3d_idx%get('dz'))
      this%zt => this%mete3d(:, :, :, this%m3d_idx%get('zt'))
      this%dzdt => this%mete3d(:, :, :, this%m3d_idx%get('dzdt'))
      this%rho => this%mete3d(:, :, :, this%m3d_idx%get('rho'))

      this%volume => this%mete3d(:, :, :, this%m3d_idx%get('volume'))
      this%thetav => this%mete3d(:, :, :, this%m3d_idx%get('thetav'))

      this%T => this%mete3d(:, :, :, this%m3d_idx%get('T'))
      this%P => this%mete3d(:, :, :, this%m3d_idx%get('P'))
      this%kx => this%mete3d(:, :, :, this%m3d_idx%get('kx'))
      this%ky => this%mete3d(:, :, :, this%m3d_idx%get('ky'))
      this%kz => this%mete3d(:, :, :, this%m3d_idx%get('kz'))

      this%TSK => this%mete2d(:, :, this%m2d_idx%get('TSK'))
      this%PBL => this%mete2d(:, :, this%m2d_idx%get('PBLH'))
      this%RMOL => this%mete2d(:, :, this%m2d_idx%get('RMOL'))
      this%PSFC => this%mete2d(:, :, this%m2d_idx%get('PSFC'))
      this%ustar => this%mete2d(:, :, this%m2d_idx%get('ustar'))
      this%wstar => this%mete2d(:, :, this%m2d_idx%get('wstar'))
      this%Ri => this%mete2d(:, :, this%m2d_idx%get('Ri'))

   end subroutine block_init

   subroutine block_update_bc(this, tile, parent_grid_ratio)
      !! 更新边界条件
      class(block_type), intent(inout) :: this
      type(tile_type), intent(in) :: tile   !! 切片信息
      integer, optional, intent(in) :: parent_grid_ratio !! 父子区域的网格分辨率比

      integer :: i, j, k, idx, jdx, ratio

      ratio = 1
      if (present(parent_grid_ratio)) ratio = parent_grid_ratio
      if (ratio > 1) then ! 子区域
         do k = 1, 4 ! 东西南北
            if (this%edges(k)%is_edge) then
               do j = 1, this%edges(k)%ny
                  jdx = 1
                  if (k == west .or. k == east) jdx = 1 + (j + tile%jds - 2)/ratio
                  do i = 1, this%edges(k)%nx ! 默认只传输一个宽度父区域数据
                     idx = 1
                     if (k == south .or. k == north) idx = 1 + (i + tile%ids - 2)/ratio
                     this%edges(k)%bc(i, j, :, :) = this%coarse_edges(k)%bc(idx, jdx, :, :)
                  end do
               end do
            end if
         end do
      end if

      if (this%edges(west)%is_edge) then
         this%chem3d(this%iws:this%iwe, this%jbs:this%jbe, :, :, this%twindow) = this%edges(west)%bc
      end if
      if (this%edges(east)%is_edge) then
         this%chem3d(this%ies:this%iee, this%jbs:this%jbe, :, :, this%twindow) = this%edges(east)%bc
      end if
      if (this%edges(south)%is_edge) then
         this%chem3d(this%ibs:this%ibe, this%jss:this%jse, :, :, this%twindow) = this%edges(south)%bc
      end if
      if (this%edges(north)%is_edge) then
         this%chem3d(this%ibs:this%ibe, this%jns:this%jne, :, :, this%twindow) = this%edges(north)%bc
      end if
   end subroutine block_update_bc

   subroutine block_clear(this)

      class(block_type), intent(inout) :: this
      integer :: direction

      nullify (this%u, this%v, this%w, this%dz, this%zt, this%dzdt)
      nullify (this%rho, this%rho_cctm, this%volume)
      nullify (this%T, this%thetav, this%TSK, this%P, this%PSFC)
      nullify (this%PBL, this%Ri, this%RMOL, this%ustar, this%wstar)
      nullify (this%kx, this%ky, this%kz)
      if (allocated(this%chem3d)) deallocate (this%chem3d)
      if (allocated(this%emis3d)) deallocate (this%emis3d)
      if (allocated(this%terrain)) deallocate (this%terrain)
      if (allocated(this%mete2d)) deallocate (this%mete2d)
      if (allocated(this%mete2d_1)) deallocate (this%mete2d_1)
      if (allocated(this%mete2d_2)) deallocate (this%mete2d_2)
      if (allocated(this%mete3d)) deallocate (this%mete3d)
      if (allocated(this%mete3d_1)) deallocate (this%mete3d_1)
      if (allocated(this%mete3d_2)) deallocate (this%mete3d_2)
      if (allocated(this%rho_next)) deallocate (this%rho_next)
      do direction = 1, 4
         if (allocated(this%edges(direction)%bc)) deallocate (this%edges(direction)%bc)
         if (allocated(this%coarse_edges(direction)%bc)) deallocate (this%coarse_edges(direction)%bc)
      end do
      call this%m2d_idx%clear()
      call this%m3d_idx%clear()
      call this%mesh%clear()

   end subroutine block_clear

   subroutine block_final(this)

      type(block_type), intent(inout) :: this

      call this%clear()

   end subroutine block_final

end module mod_block
