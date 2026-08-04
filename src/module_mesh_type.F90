module mod_mesh
   !! 结构化网格

   use mod_const, only: fp, pi, pi2, radius, rad, eps
   use mod_error, only: fatal_error

   use projection, only: proj_type, PROJ_SUCCESS

   implicit none

   private

   public mesh_type

   type mesh_type !! 格点网数据结构
      integer :: nx = 0         !! Local X-cell count including halo. / 包含 halo 的局地 X 格点数。
      integer :: ny = 0         !! Local Y-cell count including halo. / 包含 halo 的局地 Y 格点数。

      integer :: proj_id = 0    !! Projection code; 0 denotes latlon. / 投影编号；0 表示等经纬度。
      real(fp) :: xorg = 0.0_fp !! Southwest X coordinate [degree or m]. / 西南角 X 坐标 [度或米]。
      real(fp) :: yorg = 0.0_fp !! Southwest Y coordinate [degree or m]. / 西南角 Y 坐标 [度或米]。
      real(fp) :: delta = 81000.0_fp !! Uniform spacing [degree or m]. / 均匀网格间距 [度或米]。

      real(fp), allocatable :: mlon(:, :) !! mass grid, 经度(nx, ny)
      real(fp), allocatable :: mlat(:, :) !! mass grid, 纬度(nx, ny)
      real(fp), allocatable :: clon(:, :) !! grid corner: nx+1, ny+1
      real(fp), allocatable :: clat(:, :) !! grid corner: nx+1, ny+1
      real(fp), allocatable :: xlen(:, :) !! 近似四边形的x方向长度;
      real(fp), allocatable :: ylen(:, :) !! 近似四边形的y方向长度;
      real(fp), allocatable :: area(:, :) !! 网格面积

      real(fp), allocatable :: dx_mean(:) !! x方向的平均距离;
      real(fp), allocatable :: dy_mean(:) !! y方向的平均距离;

   contains
      procedure :: cal_area !! 计算网格面积: 根据经纬度，计算面积
      procedure :: init => mesh_init !! 初始化
      procedure :: clear => mesh_clear !! 初始化
   end type mesh_type

contains

   subroutine mesh_init(this, xorg, yorg, delta, nx, ny, proj_id, p)
      !! 需要包含边界输送的面积订正问题
      class(mesh_type), intent(inout) :: this
      real(fp), intent(in) :: xorg   !! 区域左下角起始点网格
      real(fp), intent(in) :: yorg   !! 区域左下角起始点网格
      real(fp), intent(in) :: delta  !! 经纬度, 或者米?
      integer, intent(in) :: nx     !! 网格数
      integer, intent(in) :: ny     !! 网格数
      integer, intent(in) :: proj_id !! 网格投影类型；0 表示等经纬度网格
      type(proj_type), intent(in) :: p  !! 投影信息

      ! Local variables / 局部变量
      integer :: i, j, proj_stat
      real(fp) :: x, y  ! 中心点
      real(fp) :: x_dash, y_dash !边角点
      character(:), allocatable :: proj_message

      this%nx = nx
      this%ny = ny
      this%xorg = xorg
      this%yorg = yorg
      this%delta = delta
      this%proj_id = proj_id

      !! 多一圈
      allocate (this%mlat(this%nx, this%ny))
      allocate (this%mlon(this%nx, this%ny))
      allocate (this%xlen(this%nx, this%ny))
      allocate (this%ylen(this%nx, this%ny))
      allocate (this%area(this%nx, this%ny))

      allocate (this%dx_mean(this%ny))
      allocate (this%dy_mean(this%nx))

      !! 每个网格四个角的经纬度
      allocate (this%clat(this%nx + 1, this%ny + 1))
      allocate (this%clon(this%nx + 1, this%ny + 1))

      if (this%proj_id == 0) then !! 等经纬度网格
         do i = 1, this%nx + 1
            this%clon(i, :) = this%xorg + (i - 1)*delta
            if (i <= this%nx) this%mlon(i, :) = this%xorg + (i - 0.5)*delta
         end do
         do j = 1, this%ny + 1
            this%clat(:, j) = this%yorg + (j - 1)*delta
            if (j <= this%ny) this%mlat(:, j) = this%yorg + (j - 0.5)*delta
         end do
      else !! 投影网格（Lambert、Mercator 等）
         do j = 1, this%ny + 1 ! 内循环，列优先
            y = this%yorg + (j - 0.5)*delta
            y_dash = this%yorg + (j - 1)*delta
            do i = 1, this%nx + 1 ! 内循环，列优先
               x = this%xorg + (i - 0.5)*delta
               x_dash = this%xorg + (i - 1)*delta
               call p%xy_to_ll(x_dash, y_dash, this%clon(i, j), this%clat(i, j), &
                               stat=proj_stat, errmsg=proj_message)
               if (proj_stat /= PROJ_SUCCESS) &
                  call fatal_error('corner-coordinate projection failed: '//proj_message)
               if (j <= this%ny .and. i <= this%nx) then
                  call p%xy_to_ll(x, y, this%mlon(i, j), this%mlat(i, j), &
                                  stat=proj_stat, errmsg=proj_message)
                  if (proj_stat /= PROJ_SUCCESS) &
                     call fatal_error('mass-coordinate projection failed: '//proj_message)
               end if
            end do
         end do
      end if

      where (this%mlon > +180.) this%mlon = this%mlon - 360.
      where (this%clon > +180.) this%clon = this%clon - 360.
      where (this%mlon < -180.) this%mlon = this%mlon + 360.
      where (this%clon < -180.) this%clon = this%clon + 360.
      where (this%mlat > +90.) this%mlat = 180 - this%mlat
      where (this%clat > +90.) this%clat = 180 - this%clat
      where (this%mlat < -90.) this%mlat = -(180 + this%mlat)
      where (this%clat < -90.) this%clat = -(180 + this%clat)

      !! 计算面积
      call this%cal_area()

      !! 计算长和宽: 近似正方形, x方向的距离变形一般比较严重
      do j = 1, this%ny
         do i = 1, this%nx
          this%ylen(i, j) = great_circle(radius, this%mlon(i, j), this%clat(i, j), this%mlon(i, j), this%clat(i, j + 1))
            this%xlen(i, j) = this%area(i, j)/this%ylen(i, j)
         end do
      end do

      if (this%proj_id > 0) then
         this%dx_mean = this%delta
         this%dy_mean = this%delta
      else
         do j = 1, this%ny
            ! this%dx_mean(j) = sum(this%xlen(:, j))/this%nx ! 会导致不同核心出现差异
            this%dx_mean(j) = nint(sum(this%xlen(:, j))/this%nx*100._fp)/100._fp
         end do
         do i = 1, this%nx
            ! this%dy_mean(i) = sum(this%ylen(i, :))/this%ny
            this%dy_mean(i) = nint(sum(this%ylen(i, :))/this%ny*100._fp)/100._fp
         end do
      end if

   end subroutine mesh_init

   subroutine mesh_clear(this)
      !! 释放数组资源
      class(mesh_type), intent(inout) :: this
      if (allocated(this%mlat)) deallocate (this%mlat)
      if (allocated(this%mlon)) deallocate (this%mlon)
      if (allocated(this%xlen)) deallocate (this%xlen)
      if (allocated(this%ylen)) deallocate (this%ylen)
      if (allocated(this%area)) deallocate (this%area)
      if (allocated(this%clat)) deallocate (this%clat)
      if (allocated(this%clon)) deallocate (this%clon)
      if (allocated(this%dx_mean)) deallocate (this%dx_mean)
      if (allocated(this%dy_mean)) deallocate (this%dy_mean)
   end subroutine mesh_clear

   subroutine cal_area(this)
      !!  验证 data.area.sum()/(6371**2 * 4 * np.pi)
      implicit none
      ! Input Args
      class(mesh_type), intent(inout) :: this     ! mgridection info structure
      ! Locals
      integer :: i, j, k
      real(fp), dimension(3, 4) :: p !! [(x, y, z), npoints]

      do j = 1, this%ny
         do i = 1, this%nx
            call lonlat2xyz(radius, this%clon(i, j), this%clat(i, j), p(1, 1), p(2, 1), p(3, 1))
            call lonlat2xyz(radius, this%clon(i + 1, j), this%clat(i + 1, j), p(1, 2), p(2, 2), p(3, 2))
            call lonlat2xyz(radius, this%clon(i + 1, j + 1), this%clat(i + 1, j + 1), p(1, 3), p(2, 3), p(3, 3))
            call lonlat2xyz(radius, this%clon(i, j + 1), this%clat(i, j + 1), p(1, 4), p(2, 4), p(3, 4))
            do k = 1, 4 !! 极点
               if (abs(p(3, k)) == radius) p(1:2, k) = 0
            end do
            !! 没有处理极点在中间的情况，根据上一步的处理，这种情况不可能出现
            if (abs(p(3, 1)) == radius .and. any(abs(p(3, 2:4)) == radius)) then
               this%area(i, j) = spherical_area(radius, p(1, 2:4), p(2, 2:4), p(3, 2:4))
            else if (abs(p(3, 4)) == radius .and. any(abs(p(3, 1:3)) == radius)) then
               this%area(i, j) = spherical_area(radius, p(1, 1:3), p(2, 1:3), p(3, 1:3))
            else
               this%area(i, j) = spherical_area(radius, p(1, :), p(2, :), p(3, :))
            end if
         end do
      end do
   end subroutine cal_area

   subroutine lonlat2xyz(R, lon, lat, x, y, z)
      !! 球坐标转换为笛卡尔坐标
      real(fp), intent(in) :: R
      real(fp), intent(in) :: lon, lat
      real(fp), intent(out) :: x, y, z
      x = R*cos(lat*rad)*cos(lon*rad)
      y = R*cos(lat*rad)*sin(lon*rad)
      z = R*sin(lat*rad)
   end subroutine lonlat2xyz

   pure function cross_product(x, y) result(r)
      !! 求两个点的叉积
      real(fp), intent(in) :: x(3)
      real(fp), intent(in) :: y(3)
      real(fp) :: r(3)
      r(1) = x(2)*y(3) - x(3)*y(2)
      r(2) = x(3)*y(1) - x(1)*y(3)
      r(3) = x(1)*y(2) - x(2)*y(1)
   end function cross_product

   real(fp) function spherical_area(R, x, y, z) result(area)
      !!  简单球面多边形面积公式
      !!  A = R**2 * (E−(n-2)π)
      real(fp), intent(in) :: R
      real(fp), intent(in) :: x(:)
      real(fp), intent(in) :: y(:)
      real(fp), intent(in) :: z(:)
      integer :: i, n
      integer im1, ip1
      real(fp) angle, e

      n = size(x)
      if (n < 3) then
         call fatal_error('cannot calculate the area of a spherical polygon with fewer than three vertices')
      end if
      angle = 0.0
      do i = 1, n ! 计算每个角的和
         im1 = merge(i - 1, n, i /= 1)
         ip1 = merge(i + 1, 1, i /= n)
         angle = angle + spherical_angle([x(im1), y(im1), z(im1)], [x(i), y(i), z(i)], [x(ip1), y(ip1), z(ip1)])
      end do
      area = R**2*(angle - (n - 2)*pi)

   end function spherical_area

   pure real(fp) function spherical_angle(a, b, c) result(angle)
      !! 法向量之间的点积计算每个顶点的角度
      real(fp), intent(in) :: a(3)
      real(fp), intent(in) :: b(3)
      real(fp), intent(in) :: c(3)

      real(fp) nab(3) ! Normal vector of plane AB
      real(fp) nbc(3) ! Normal vector of plane BC

      nab = norm_vector(cross_product(a, b))
      nbc = norm_vector(cross_product(b, c))
      angle = acos(-max(min(dot_product(nab, nbc), 1.0), -1.0))

      ! Judge the cyclic direction with respect to point A to handle obtuse angle.
      if (dot_product(cross_product(nab, nbc), a) < 0.0) angle = pi2 - angle

   end function spherical_angle

   pure function norm_vector(x) result(norm)
      !! 计算法向量
      real(fp), intent(in) :: x(:)
      real(fp) :: norm(size(x))

      real(fp) :: tmp

      tmp = sqrt(sum(x*x))
      if (tmp /= 0) then
         norm = x/tmp
      else
         norm = x
      end if
   end function norm_vector

   pure real(fp) function great_circle(R, lon1, lat1, lon2, lat2) result(circle)
      !! 球体表面上两点之间的大圆距离
      real(fp), intent(in) :: R
      real(fp), intent(in) :: lon1
      real(fp), intent(in) :: lat1
      real(fp), intent(in) :: lon2
      real(fp), intent(in) :: lat2
      real(fp) :: v
      v = sin(lat1*rad)*sin(lat2*rad) + cos(lat1*rad)*cos(lat2*rad)*cos(lon1*rad - lon2*rad)
      circle = R*acos(min(1.0, max(-1.0, v)))
   end function great_circle

end module mod_mesh
