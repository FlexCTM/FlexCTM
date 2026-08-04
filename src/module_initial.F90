module mod_initial
  !! 初始条件
   use netcdf

   use mod_block, only: block_type
   use mod_tool, only: does_file_exist
   use mod_ncio, only: nc_type, check_netcdf, open_nc_file, close_nc_file

   use parallel, only: process_type, domain_type, tile_type

   implicit none
   private

   public :: initialize_chemistry

contains

   subroutine initialize_chemistry(proc, domain, tile, iblock, filename)
    !! 从统一 NetCDF 格式读取化学初始场；文件缺失时使用零场。
      type(process_type), intent(in) :: proc        !! 当前进程
      type(domain_type), intent(in) :: domain      !! 当前区域
      type(tile_type), intent(in) :: tile        !! 当前数据切片
      type(block_type), intent(inout) :: iblock     !! 当前数据块
      character(len=*), intent(in) :: filename   !! 文件名称

      ! local variable
      type(nc_type) :: fh
      integer :: i, t, ierr
      integer :: varid

      t = iblock%twindow
      iblock%chem3d = 0
      if (.not. does_file_exist(filename)) then
         return
      end if

      if (proc%is_root()) write (*, *) '    open ', trim(filename)
      fh = open_nc_file(proc, domain, tile, filename, is_read=.true.)
      do i = 1, iblock%chem_meta%nvar
         if (iblock%chem_meta%vars(i)%read_initial) then
            ierr = nf90_inq_varid(fh%id, iblock%chem_meta%vars(i)%name, varid)
            if (ierr == nf90_noerr) then
               if (proc%is_root()) write (*, *) '       **reading init: ', iblock%chem_meta%vars(i)%name
               call check_netcdf(nf90_get_var(fh%id, varid, &
                                       iblock%chem3d(fh%ibs:fh%ibe, fh%jbs:fh%jbe, :, i, t), &
                                       start=fh%start3d, count=fh%count3d), 'reading initial field', &
                          filename, iblock%chem_meta%vars(i)%name)
            end if
         end if
      end do
      call close_nc_file(fh)
   end subroutine initialize_chemistry

end module mod_initial
