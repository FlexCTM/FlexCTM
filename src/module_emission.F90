module mod_emission
   !! 读取排放数据

   use netcdf

   use mod_block, only: block_type
   use mod_const, only: fp

   use mod_tool, only: does_file_exist
   use mod_ncio, only: nc_type, check_netcdf, open_nc_file, close_nc_file

   use parallel, only: process_type, domain_type, tile_type

   implicit none
   private

   public :: update_emission

contains

   subroutine update_emission(proc, domain, tile, iblock, filename, nlev)
      !! 读取统一 NetCDF 排放；文件缺失时生成确定性 MOCK 排放。
      type(process_type), intent(in) :: proc        !! 当前进程
      type(domain_type), intent(in) :: domain      !! 当前区域
      type(tile_type), intent(in) :: tile        !! 当前数据切片
      type(block_type), intent(inout) :: iblock     !! 当前数据块
      character(len=*), intent(in) :: filename   !! 文件名称
      integer, intent(in) :: nlev !! 排放文件给的高度

      ! local variable
      type(nc_type) :: fh
      integer :: i
      integer :: varid
      integer :: ierr

      if (.not. does_file_exist(filename)) then
         if (proc%is_root()) then
            write (*, '(A)') 'WARNING: emission file "'//trim(filename)// &
                             '" does not exist; using deterministic MOCK emissions.'
         end if
         call generate_mock_emission(iblock)
         return
      end if

      iblock%emis3d = 0._fp
      fh = open_nc_file(proc, domain, tile, filename, nlev=nlev, is_read=.true.)
      do i = 1, iblock%chem_meta%nvar
         if (iblock%chem_meta%vars(i)%read_emission) then
            ierr = nf90_inq_varid(fh%id, iblock%chem_meta%vars(i)%name, varid)
            if (ierr == nf90_noerr) then
               call check_netcdf(nf90_get_var(fh%id, varid, &
                                       iblock%emis3d(fh%ibs:fh%ibe, fh%jbs:fh%jbe, 1:nlev, i), &
                                       start=fh%start3d, count=fh%count3d), 'reading emission', &
                          filename, iblock%chem_meta%vars(i)%name)
            end if
         end if
      end do
      call close_nc_file(fh)
   end subroutine update_emission

   subroutine generate_mock_emission(iblock)
      !! 为缺失排放文件的开发运行生成平滑、可重复的近地层源项。
      type(block_type), intent(inout) :: iblock
      real(fp) :: latitude, longitude, source_pattern, strength
      integer :: i, j, n

      iblock%emis3d = 0._fp
      do n = 1, iblock%chem_meta%nvar
         if (.not. iblock%chem_meta%vars(n)%read_emission) cycle
         strength = mock_emission_strength(iblock%chem_meta%vars(n)%name)
         do j = 1, iblock%ny
            do i = 1, iblock%nx
               latitude = iblock%mesh%mlat(i, j)
               longitude = iblock%mesh%mlon(i, j)
               source_pattern = exp(-((longitude - 115._fp)/18._fp)**2 - &
                                    ((latitude - 35._fp)/12._fp)**2) + &
                                0.7_fp*exp(-((longitude + 80._fp)/22._fp)**2 - &
                                           ((latitude - 40._fp)/14._fp)**2)
               iblock%emis3d(i, j, 1, n) = strength*source_pattern
            end do
         end do
      end do
   end subroutine generate_mock_emission

   real(fp) function mock_emission_strength(name) result(value)
      character(len=*), intent(in) :: name

      select case (trim(name))
      case ('CO'); value = 2._fp
      case ('NO', 'NO2'); value = 0.4_fp
      case ('SO2'); value = 0.25_fp
      case ('NH3'); value = 0.3_fp
      case ('SO4', 'NO3', 'NH4'); value = 0.05_fp
      case default; value = 0._fp
      end select
   end function mock_emission_strength

end module mod_emission
