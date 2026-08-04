module mod_output
   !! FlexCTM 模式状态的 NetCDF 输出。
   use netcdf
   use mod_const, only: fp
   use mod_block, only: block_type
   use mod_ncio, only: nc_type, check_netcdf, model_netcdf_type
   use mod_ncio, only: open_nc_file, close_nc_file
   use mod_chem_type, only: chem_table_type
   use parallel, only: process_type, domain_type, tile_type

   implicit none
   private

   public :: write_static_output, write_model_output
   public :: write_field

   interface write_field
      module procedure write_field2d_to_nc
      module procedure write_field3d_to_nc
   end interface

contains

   subroutine write_static_output(proc, domain, tile, iblock, filename)
      !! 写出网格坐标、面积和地形等静态场。
      type(process_type), intent(in) :: proc
      type(domain_type), intent(in) :: domain
      type(tile_type), intent(in) :: tile
      type(block_type), intent(in) :: iblock
      character(len=*), intent(in) :: filename

      type(nc_type) :: fh

      if (proc%is_root()) write (*, *) 'write static: ', trim(filename)
      fh = open_nc_file(proc, domain, tile, filename)
      call write_field(fh, 'mlat', iblock%mesh%mlat, &
                       unit='degree', description='latitude of mass grid')
      call write_field(fh, 'mlon', iblock%mesh%mlon, &
                       unit='degree', description='longitude of mass grid')
      call write_field(fh, 'area', iblock%mesh%area, &
                       unit='m^2', description='grid-cell area')
      call write_field(fh, 'terrain', iblock%terrain, &
                       unit='m', description='terrain height')
      call close_nc_file(fh)
   end subroutine write_static_output

   subroutine write_model_output(proc, domain, tile, iblock, filename)
      !! 将当前化学状态和 output=true 的气象场写入同一文件。
      type(process_type), intent(in) :: proc
      type(domain_type), intent(in) :: domain
      type(tile_type), intent(in) :: tile
      type(block_type), intent(in) :: iblock
      character(len=*), intent(in) :: filename

      type(nc_type) :: fh
      integer :: n

      if (proc%is_root()) write (*, *) 'write output: ', trim(filename)
      fh = open_nc_file(proc, domain, tile, filename)
      call write_chem_fields(fh, iblock%chem_meta, &
                             iblock%chem3d(:, :, :, :, iblock%twindow))

      do n = 1, iblock%mete_table%n_2d
         if (iblock%mete_table%var2ds(n)%output) then
            call write_field(fh, iblock%mete_table%var2ds(n)%name, &
                             iblock%mete2d(:, :, n), iblock%mete_table%var2ds(n)%unit, &
                             iblock%mete_table%var2ds(n)%description)
         end if
      end do
      do n = 1, iblock%mete_table%n_3d
         if (iblock%mete_table%var3ds(n)%output) then
            call write_field(fh, iblock%mete_table%var3ds(n)%name, &
                             iblock%mete3d(:, :, :, n), iblock%mete_table%var3ds(n)%unit, &
                             iblock%mete_table%var3ds(n)%description)
         end if
      end do
      call close_nc_file(fh)
   end subroutine write_model_output

   subroutine write_chem_fields(fh, meta, field)
      type(nc_type), intent(in) :: fh    !! nc文件句柄
      type(chem_table_type), intent(in) :: meta  !! 输出文件名称
      real(fp), intent(in) :: field(:, :, :, :)   !! x, y, z, variable
      integer :: i

      do i = 1, meta%nvar
         if (meta%vars(i)%write_output) then
            if (meta%vars(i)%name == 'rho') then
               call write_field(fh, 'rho_cctm', field(:, :, :, i), meta%vars(i)%unit, meta%vars(i)%description)
            else
               call write_field(fh, meta%vars(i)%name, field(:, :, :, i), meta%vars(i)%unit, meta%vars(i)%description)
            end if
         end if
      end do

   end subroutine write_chem_fields

   subroutine write_field2d_to_nc(fh, varname, field, unit, description)
      !! 并行写出数据: 可以用Assumed-rank arrays改造(2018的语法特征)
      type(nc_type), intent(in) :: fh   !! nc文件句柄
      character(len=*), intent(in) :: varname     !! 输出文件名称
      real(fp), intent(in) :: field(:, :)   !! 当前变量
      character(len=*), optional, intent(in) :: unit     !! 输出文件名称
      character(len=*), optional, intent(in) :: description     !! 输出文件名称

      integer :: varid !! NetCDF identifier assigned to the 2-D variable. / NetCDF 为二维变量分配的 ID。
      call check_netcdf(nf90_redef(fh%id), 'entering NetCDF define mode', fh%filename)
      call check_netcdf(nf90_def_var(fh%id, varname, model_netcdf_type, fh%dims(1:2), varid), &
                 'defining NetCDF variable', fh%filename, varname)
      if (present(unit)) call check_netcdf(NF90_PUT_ATT(fh%id, varid, 'unit', trim(unit)), &
                                    'writing unit attribute', fh%filename, varname)
      if (present(description)) call check_netcdf(NF90_PUT_ATT(fh%id, varid, 'description', trim(description)), &
                                           'writing description attribute', fh%filename, varname)
      call check_netcdf(nf90_enddef(fh%id), 'ending NetCDF define mode', fh%filename)

      ! Unlimited dimensions require collective writes
      call check_netcdf(nf90_var_par_access(fh%id, varid, nf90_collective), &
                 'setting collective access', fh%filename, varname)
      ! The unlimited axis prevents independent write tests
      ! Re-enable the rank test if independent writes are used in the future
      ! NOTICE: fortran index starts form 1!
      call check_netcdf(nf90_put_var(fh%id, varid, field(fh%ibs:fh%ibe, fh%jbs:fh%jbe), &
                              start=fh%start2d, count=fh%count2d), 'writing NetCDF variable', fh%filename, varname)
   end subroutine write_field2d_to_nc

   subroutine write_field3d_to_nc(fh, varname, field, unit, description)
    !! 并行写出数据: 可以用Assumed-rank arrays改造(2018的语法特征)
      type(nc_type), intent(in) :: fh   !! nc文件句柄
      character(len=*), intent(in) :: varname     !! 输出文件名称
      real(fp), intent(in) :: field(:, :, :)   !! 当前变量
      character(len=*), optional, intent(in) :: unit     !! 输出文件名称
      character(len=*), optional, intent(in) :: description     !! 输出文件名称

      integer :: varid !! NetCDF identifier assigned to the 3-D variable. / NetCDF 为三维变量分配的 ID。
      call check_netcdf(nf90_redef(fh%id), 'entering NetCDF define mode', fh%filename)
      call check_netcdf(nf90_def_var(fh%id, varname, model_netcdf_type, fh%dims(1:3), varid), &
                 'defining NetCDF variable', fh%filename, varname)
      if (present(unit)) call check_netcdf(NF90_PUT_ATT(fh%id, varid, 'unit', trim(unit)), &
                                    'writing unit attribute', fh%filename, varname)
      if (present(description)) call check_netcdf(NF90_PUT_ATT(fh%id, varid, 'description', trim(description)), &
                                           'writing description attribute', fh%filename, varname)
      call check_netcdf(nf90_enddef(fh%id), 'ending NetCDF define mode', fh%filename)

      ! Unlimited dimensions require collective writes
      call check_netcdf(nf90_var_par_access(fh%id, varid, nf90_collective), &
                 'setting collective access', fh%filename, varname)
      ! The unlimited axis prevents independent write tests
      ! Re-enable the rank test if independent writes are used in the future
      ! NOTICE: fortran index starts form 1!
      call check_netcdf(nf90_put_var(fh%id, varid, field(fh%ibs:fh%ibe, fh%jbs:fh%jbe, :), &
                              start=fh%start3d, count=fh%count3d), 'writing NetCDF variable', fh%filename, varname)
   end subroutine write_field3d_to_nc

end module mod_output
