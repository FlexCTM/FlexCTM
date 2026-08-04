module mod_ncio
   !! NetCDF 文件生命周期、并行打开选项和错误处理。
   use netcdf
   use mpi

   use mod_const, only: fp
   use mod_error, only: fatal_error
   use parallel, only: process_type, domain_type, tile_type

   implicit none
   private

   public :: nc_type
   public :: open_nc_file, close_nc_file
   public :: check_netcdf, resolve_nc_open_options
   public :: model_netcdf_type

   integer, parameter :: model_netcdf_type = merge(NF90_FLOAT, NF90_DOUBLE, storage_size(0.0_fp) == 32)

   type nc_type
      integer :: id                         !! NetCDF 文件标识符。
      character(:), allocatable :: filename !! 用于错误诊断的文件路径。
      integer :: dims(3)                    !! 按 [x,y,z] 排列的维度 ID。
      integer :: start2d(2)                 !! 二维局地块在全局场中的一基起点 [x,y]。
      integer :: count2d(2)                 !! 二维局地有效格点数 [x,y]。
      integer :: start3d(3)                 !! 三维局地块在全局场中的一基起点 [x,y,z]。
      integer :: count3d(3)                 !! 三维局地有效格点数 [x,y,z]。
      integer :: ibs, ibe                    !! 不含 halo 的局地有效 X 起止下标。
      integer :: jbs, jbe                    !! 不含 halo 的局地有效 Y 起止下标。
   end type nc_type

contains

   type(nc_type) function open_nc_file(proc, domain, tile, filename, nlev, is_old, is_read) result(fh)
      !! 打开或创建 NetCDF 文件，并初始化局地数据切片信息。
      type(process_type), intent(in) :: proc     !! 当前进程信息。
      type(domain_type), intent(in) :: domain   !! 当前计算区域。
      type(tile_type), intent(in) :: tile       !! 当前进程的数据切片。
      character(len=*), intent(in) :: filename !! NetCDF 文件路径。
      integer, optional, intent(in) :: nlev     !! 可选的垂直层数。
      logical, optional, intent(in) :: is_old   !! 是否打开已有文件。
      logical, optional, intent(in) :: is_read  !! 是否以只读方式打开。

      integer :: nz             !! 实际使用的垂直层数。
      logical :: open_existing  !! 是否打开已有文件。
      logical :: read_only      !! 是否采用只读方式。

      nz = domain%nz
      if (present(nlev)) nz = nlev

      fh%filename = trim(filename)
      call resolve_nc_open_options(is_old, is_read, open_existing, read_only)

      if (read_only) then
         call check_netcdf(nf90_open(filename, NF90_NOWRITE, fh%id), 'opening read-only NetCDF', filename)
      else if (open_existing) then
         call check_netcdf( nf90_open(filename, IOR(NF90_NETCDF4, IOR(NF90_WRITE, NF90_MPIIO)), &
                      fh%id, comm=proc%model%comm, info=MPI_INFO_NULL), 'opening writable NetCDF', filename)
      else
         call check_netcdf( nf90_create(filename, IOR(NF90_NETCDF4, NF90_MPIIO), fh%id, comm=proc%model%comm, info=MPI_INFO_NULL), &
            'creating NetCDF', filename)
      end if

      if (.not. open_existing) then
         call check_netcdf(nf90_def_dim(fh%id, 'x', domain%nx, fh%dims(1)), 'defining dimension x', filename)
         call check_netcdf(nf90_def_dim(fh%id, 'y', domain%ny, fh%dims(2)), 'defining dimension y', filename)
         call check_netcdf(nf90_def_dim(fh%id, 'z', nz, fh%dims(3)), 'defining dimension z', filename)
         call check_netcdf(nf90_put_att(fh%id, NF90_GLOBAL, 'description', 'naqp'), 'writing global description', filename)
         call check_netcdf(nf90_enddef(fh%id), 'ending NetCDF define mode', filename)
      else if (.not. read_only) then
         ! Read-only external datasets may use native dimension names such as WRF's west_east.
         call check_netcdf(nf90_inq_dimid(fh%id, 'x', fh%dims(1)), 'querying dimension x', filename)
         call check_netcdf(nf90_inq_dimid(fh%id, 'y', fh%dims(2)), 'querying dimension y', filename)
         call check_netcdf(nf90_inq_dimid(fh%id, 'z', fh%dims(3)), 'querying dimension z', filename)
      end if

      ! 只处理当前切片中的有效区域，不包含 halo。
      fh%ibs = tile%ibs
      fh%ibe = tile%ibe
      fh%jbs = tile%jbs
      fh%jbe = tile%jbe
      fh%start2d = [tile%ids, tile%jds]
      fh%count2d = [tile%nx, tile%ny]
      fh%start3d = [tile%ids, tile%jds, 1]
      fh%count3d = [tile%nx, tile%ny, nz]
   end function open_nc_file

   subroutine resolve_nc_open_options(is_old, is_read, open_existing, read_only)
      !! 将可选参数归一化；只读模式必然表示打开已有文件。
      logical, optional, intent(in) :: is_old  !! 是否打开已有文件。
      logical, optional, intent(in) :: is_read !! 是否以只读方式打开。
      logical, intent(out) :: open_existing    !! 归一化后的已有文件标志。
      logical, intent(out) :: read_only        !! 归一化后的只读标志。

      open_existing = .false.
      read_only = .false.
      if (present(is_old)) open_existing = is_old
      if (present(is_read)) read_only = is_read
      if (read_only) open_existing = .true.
   end subroutine resolve_nc_open_options

   subroutine close_nc_file(fh)
      !! 关闭 NetCDF 文件并刷新内部缓冲区。
      type(nc_type), intent(in) :: fh !! 待关闭的 NetCDF 文件句柄。

      call check_netcdf(nf90_close(fh%id), 'closing NetCDF', fh%filename)
   end subroutine close_nc_file

   subroutine check_netcdf(status, operation, filename, variable)
      !! 检查 NetCDF 状态码，并向应用层报告包含上下文的致命错误。
      integer, intent(in) :: status                  !! NetCDF API 返回的状态码。
      character(len=*), optional, intent(in) :: operation !! 正在执行的操作。
      character(len=*), optional, intent(in) :: filename  !! 相关文件路径。
      character(len=*), optional, intent(in) :: variable  !! 相关变量名称。

      character(:), allocatable :: message !! 组合后的错误诊断信息。

      if (status /= nf90_noerr) then
         message = 'NetCDF operation failed'
         if (present(operation)) message = trim(operation)//' failed'
         if (present(filename)) message = message//' for file "'//trim(filename)//'"'
         if (present(variable)) message = message//' variable "'//trim(variable)//'"'
         message = message//': '//trim(nf90_strerror(status))
         call fatal_error(message, 2)
      end if
   end subroutine check_netcdf

end module mod_ncio
