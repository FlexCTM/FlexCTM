module mod_meteorology_wrf
   !! WRF NetCDF 数据读取及数据集特有诊断。
   use netcdf

   use mod_const, only: g, fp, Rd, RvRd, R_cp, P00
   use mod_error, only: fatal_error
   use mod_block, only: block_type
   use mod_mete_type, only: METE_INPUT_RAW, mete_mapping_type
   use mod_mete_type, only: mete_mapping_table_type
   use mod_tool, only: does_file_exist
   use mod_ncio, only: nc_type, check_netcdf, open_nc_file, close_nc_file

   use parallel, only: west, east, south
   use parallel, only: process_type, domain_type, tile_type

   implicit none
   private

   public :: read_mete_field, read_mete_static

contains

   subroutine read_mete_field(proc, domain, tile, iblock, mapping, filename)
      !! 读取 WRF 数据，并在返回前生成全部 FlexCTM 标准气象变量。
      type(process_type), intent(in) :: proc        !! 当前进程。
      type(domain_type), intent(in) :: domain      !! 当前区域。
      type(tile_type), intent(in) :: tile          !! 当前数据切片。
      type(block_type), intent(inout) :: iblock    !! 当前数据块。
      type(mete_mapping_table_type), intent(in) :: mapping !! WRF 接口映射。
      character(len=*), intent(in) :: filename     !! WRF NetCDF 文件。

      type(nc_type) :: fh
      integer :: n

      if (.not. does_file_exist(filename)) &
         call fatal_error('required meteorology file does not exist: "'//trim(filename)//'"')

      fh = open_nc_file(proc, domain, tile, filename, is_read=.true.)
      do n = 1, mapping%nvar
         call execute_wrf_mapping(proc, tile, fh, iblock, mapping%vars(n))
      end do
      call close_nc_file(fh)
   end subroutine read_mete_field

   subroutine execute_wrf_mapping(proc, tile, fh, iblock, item)
      type(process_type), intent(in) :: proc
      type(tile_type), intent(in) :: tile
      type(nc_type), intent(in) :: fh
      type(block_type), intent(inout) :: iblock
      type(mete_mapping_type), intent(in) :: item

      real(fp), allocatable :: first(:, :, :), second(:, :, :)
      real(fp) :: scalar
      integer :: index, k

      if (item%ndim == 2) then
         index = iblock%m2d_idx%get(item%name)
      else
         index = iblock%m3d_idx%get(item%name)
      end if
      if (index <= 0) call fatal_error('WRF mapping target is not allocated: "'//trim(item%name)//'"')

      select case (trim(item%method))
      case ('direct')
         if (item%ndim == 2) then
            call read_raw_2d(fh, raw_name(item, 1), iblock%mete2d(:, :, index))
         else
            call read_raw_3d(fh, raw_name(item, 1), iblock%mete3d(:, :, :, index))
         end if
      case ('wrf_u_staggered')
         call read_wrf_u(proc, tile, fh, raw_name(item, 1), iblock%mete3d(:, :, :, index))
      case ('wrf_v_staggered')
         call read_wrf_v(proc, tile, fh, raw_name(item, 1), iblock%mete3d(:, :, :, index))
      case ('wrf_w_staggered')
         call read_wrf_w(fh, raw_name(item, 1), iblock%mete3d(:, :, :, index))
      case ('wrf_total_pressure')
         call allocate_raw_pair(iblock, first, second)
         call read_raw_3d(fh, raw_name(item, 1), first)
         call read_raw_3d(fh, raw_name(item, 2), second)
         iblock%mete3d(:, :, :, index) = first + second
      case ('wrf_air_temperature')
         call allocate_raw(iblock, first)
         call read_raw_3d(fh, raw_name(item, 1), first)
         call read_raw_scalar(fh, raw_name(item, 2), scalar)
         iblock%mete3d(:, :, :, index) = &
            (first + scalar)*(iblock%P/P00)**R_cp
      case ('ideal_gas_density')
         iblock%mete3d(:, :, :, index) = iblock%P/(Rd*iblock%T)
      case ('wrf_virtual_theta')
         call allocate_raw_pair(iblock, first, second)
         call read_raw_3d(fh, raw_name(item, 1), first)
         call read_raw_scalar(fh, raw_name(item, 2), scalar)
         call read_raw_3d(fh, raw_name(item, 3), second)
         iblock%mete3d(:, :, :, index) = (first + scalar)*(1._fp + RvRd*second)
      case ('wrf_layer_thickness', 'wrf_layer_top_height')
         call allocate_raw_pair(iblock, first, second, interfaces=.true.)
         call read_raw_3d(fh, raw_name(item, 1), first, interfaces=.true.)
         call read_raw_3d(fh, raw_name(item, 2), second, interfaces=.true.)
         if (trim(item%method) == 'wrf_layer_thickness') then
            do k = 1, iblock%nz
               iblock%mete3d(:, :, k, index) = &
                  (first(:, :, k + 1) + second(:, :, k + 1) - &
                   first(:, :, k) - second(:, :, k))/g
            end do
         else
            do k = 1, iblock%nz
               iblock%mete3d(:, :, k, index) = &
                  (first(:, :, k + 1) + second(:, :, k + 1) - &
                   first(:, :, 1) - second(:, :, 1))/g
            end do
         end if
      case default
         call fatal_error('unsupported WRF mapping method: "'//trim(item%method)//'"')
      end select
   end subroutine execute_wrf_mapping

   function raw_name(item, position) result(name)
      type(mete_mapping_type), intent(in) :: item
      integer, intent(in) :: position
      character(len=32) :: name

      if (position > size(item%inputs)) &
         call fatal_error('not enough inputs for WRF mapping "'//trim(item%name)//'"')
      if (item%inputs(position)%source /= METE_INPUT_RAW) &
         call fatal_error('WRF mapping method expected a raw input for "'//trim(item%name)//'"')
      name = item%inputs(position)%name
   end function raw_name

   subroutine allocate_raw(iblock, field, interfaces)
      type(block_type), intent(in) :: iblock
      real(fp), allocatable, intent(out) :: field(:, :, :)
      logical, optional, intent(in) :: interfaces
      integer :: nz

      nz = iblock%nz
      if (present(interfaces)) then
         if (interfaces) nz = nz + 1
      end if
      allocate (field(iblock%nx, iblock%ny, nz), source=0._fp)
   end subroutine allocate_raw

   subroutine allocate_raw_pair(iblock, first, second, interfaces)
      type(block_type), intent(in) :: iblock
      real(fp), allocatable, intent(out) :: first(:, :, :), second(:, :, :)
      logical, optional, intent(in) :: interfaces

      call allocate_raw(iblock, first, interfaces)
      call allocate_raw(iblock, second, interfaces)
   end subroutine allocate_raw_pair

   subroutine read_raw_scalar(fh, name, value)
      type(nc_type), intent(in) :: fh
      character(len=*), intent(in) :: name
      real(fp), intent(out) :: value
      integer :: varid

      call check_netcdf(nf90_inq_varid(fh%id, name, varid), &
                        'querying WRF variable', fh%filename, name)
      call check_netcdf(nf90_get_var(fh%id, varid, value), &
                        'reading WRF scalar', fh%filename, name)
   end subroutine read_raw_scalar

   subroutine read_raw_2d(fh, name, field)
      type(nc_type), intent(in) :: fh
      character(len=*), intent(in) :: name
      real(fp), intent(inout) :: field(:, :)
      integer :: varid

      call check_netcdf(nf90_inq_varid(fh%id, name, varid), &
                        'querying WRF variable', fh%filename, name)
      call check_netcdf(nf90_get_var(fh%id, varid, &
         field(fh%ibs:fh%ibe, fh%jbs:fh%jbe), &
         start=fh%start2d, count=fh%count2d), &
         'reading WRF variable', fh%filename, name)
   end subroutine read_raw_2d

   subroutine read_raw_3d(fh, name, field, interfaces)
      type(nc_type), intent(in) :: fh
      character(len=*), intent(in) :: name
      real(fp), intent(inout) :: field(:, :, :)
      logical, optional, intent(in) :: interfaces
      integer :: varid, count(3)

      count = fh%count3d
      if (present(interfaces)) then
         if (interfaces) count(3) = count(3) + 1
      end if
      call check_netcdf(nf90_inq_varid(fh%id, name, varid), &
                        'querying WRF variable', fh%filename, name)
      call check_netcdf(nf90_get_var(fh%id, varid, &
         field(fh%ibs:fh%ibe, fh%jbs:fh%jbe, :), &
         start=fh%start3d, count=count), &
         'reading WRF variable', fh%filename, name)
   end subroutine read_raw_3d

   subroutine read_wrf_u(proc, tile, fh, name, field)
      type(process_type), intent(in) :: proc
      type(tile_type), intent(in) :: tile
      type(nc_type), intent(in) :: fh
      character(len=*), intent(in) :: name
      real(fp), intent(inout) :: field(:, :, :)
      integer :: varid, start(3), count(3)

      start = fh%start3d
      count = fh%count3d
      call check_netcdf(nf90_inq_varid(fh%id, name, varid), &
                        'querying WRF variable', fh%filename, name)
      if (tile%ngbs(west)%is_domain_edge()) then
         count(1) = count(1) + 1
         call check_netcdf(nf90_get_var(fh%id, varid, &
            field(fh%ibs - 1:fh%ibe, fh%jbs:fh%jbe, :), start=start, count=count), &
            'reading WRF staggered U', fh%filename, name)
      else
         start(1) = start(1) + 1
         call check_netcdf(nf90_get_var(fh%id, varid, &
            field(fh%ibs:fh%ibe, fh%jbs:fh%jbe, :), start=start, count=count), &
            'reading WRF staggered U', fh%filename, name)
      end if
   end subroutine read_wrf_u

   subroutine read_wrf_v(proc, tile, fh, name, field)
      type(process_type), intent(in) :: proc
      type(tile_type), intent(in) :: tile
      type(nc_type), intent(in) :: fh
      character(len=*), intent(in) :: name
      real(fp), intent(inout) :: field(:, :, :)
      integer :: varid, start(3), count(3), beg, finish

      start = fh%start3d
      count = fh%count3d
      call check_netcdf(nf90_inq_varid(fh%id, name, varid), &
                        'querying WRF variable', fh%filename, name)
      if (tile%ngbs(south)%is_domain_edge()) then
         count(2) = count(2) + 1
         beg = fh%ibs
         finish = fh%ibe
         if (.not. tile%ngbs(west)%is_domain_edge()) then
            beg = beg - proc%nhalo
            start(1) = start(1) - proc%nhalo
            count(1) = count(1) + proc%nhalo
         end if
         if (.not. tile%ngbs(east)%is_domain_edge()) then
            finish = finish + proc%nhalo
            count(1) = count(1) + proc%nhalo
         end if
         call check_netcdf(nf90_get_var(fh%id, varid, &
            field(beg:finish, fh%jbs - 1:fh%jbe, :), start=start, count=count), &
            'reading WRF staggered V', fh%filename, name)
      else
         start(2) = start(2) + 1
         call check_netcdf(nf90_get_var(fh%id, varid, &
            field(fh%ibs:fh%ibe, fh%jbs:fh%jbe, :), start=start, count=count), &
            'reading WRF staggered V', fh%filename, name)
      end if
   end subroutine read_wrf_v

   subroutine read_wrf_w(fh, name, field)
      type(nc_type), intent(in) :: fh
      character(len=*), intent(in) :: name
      real(fp), intent(inout) :: field(:, :, :)
      integer :: varid, start(3)

      start = fh%start3d
      start(3) = start(3) + 1
      call check_netcdf(nf90_inq_varid(fh%id, name, varid), &
                        'querying WRF variable', fh%filename, name)
      call check_netcdf(nf90_get_var(fh%id, varid, &
         field(fh%ibs:fh%ibe, fh%jbs:fh%jbe, :), &
         start=start, count=fh%count3d), &
         'reading WRF staggered W', fh%filename, name)
   end subroutine read_wrf_w

   subroutine read_mete_static(proc, domain, tile, iblock, filename)
      !! 读取 WRF 静态地形数据。
      type(process_type), intent(in) :: proc
      type(domain_type), intent(in) :: domain
      type(tile_type), intent(in) :: tile
      type(block_type), intent(inout) :: iblock
      character(len=*), intent(in) :: filename

      type(nc_type) :: fh
      integer :: varid

      if (.not. does_file_exist(filename)) &
         call fatal_error('required static meteorology file does not exist: "'//trim(filename)//'"')
      fh = open_nc_file(proc, domain, tile, filename, is_read=.true.)
      call check_netcdf(nf90_inq_varid(fh%id, 'HGT', varid), &
                        'querying WRF terrain', filename, 'HGT')
      call check_netcdf(nf90_get_var(fh%id, varid, &
         iblock%terrain(fh%ibs:fh%ibe, fh%jbs:fh%jbe), &
         start=fh%start2d, count=fh%count2d), &
         'reading WRF terrain', filename, 'HGT')
      call close_nc_file(fh)
   end subroutine read_mete_static

end module mod_meteorology_wrf
