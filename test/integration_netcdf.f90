module test_integration_netcdf
   use mod_block, only: block_type
   use mod_const, only: fp
   use mod_mete_csv, only: load_mete_table
   use mod_mete_type, only: mete_table_type
   use mod_ncio, only: nc_type, check_netcdf, open_nc_file, close_nc_file
   use mod_ncio, only: model_netcdf_type
   use mod_output, only: write_static_output, write_model_output
   use mod_chem_type, only: chem_table_type
   use mod_chem_csv, only: load_chem_table
   use netcdf, only: nf90_clobber, nf90_close, nf90_create, nf90_def_dim, nf90_enddef, &
                     nf90_get_att, nf90_get_var, nf90_global, nf90_inq_varid, nf90_inquire_variable, &
                     nf90_noerr, nf90_nowrite, nf90_open
   use mpi, only: MPI_Barrier
   use parallel, only: grid_meta_type, process_type
   use projection, only: proj_type
   use testdrive, only: check, error_type, new_unittest, unittest_type
   implicit none
   private
   public :: collect_tests
contains
   subroutine collect_tests(tests)
      type(unittest_type), allocatable, intent(out) :: tests(:)
      tests = [new_unittest('parallel output interfaces', test_outputs)]
   end subroutine collect_tests

   subroutine test_outputs(error)
      type(error_type), allocatable, intent(out) :: error
      character(len=128) :: filename
      character(len=32) :: disabled_name
      type(block_type) :: block_data
      type(chem_table_type) :: chemistry
      type(mete_table_type) :: meteorology
      type(grid_meta_type) :: grid(1)
      type(process_type) :: proc
      type(proj_type) :: projection_definition
      type(nc_type) :: fh
      real(fp) :: readback(4, 4), projection_longitude
      integer :: ncid, varid, xtype, status, dimid, projection_id

      write (filename, '(A,I0,A)') '/tmp/flexctm-test-static-', storage_size(0._fp), '.nc'
      chemistry = load_chem_table('meta/species.csv')
      meteorology = load_mete_table('meta/mete.standard.csv')
      call grid(1)%init(1, 4, 4, 2, parent_id=0)
      call proc%init(grid, 1, chemistry%nvar, is_global=.false.)
      call block_data%init(proc%bridges(1), proc%tiles(1), 2, 1, chemistry, meteorology, 1)
      call block_data%mesh%init(-3._fp, -3._fp, 1._fp, block_data%nx, block_data%ny, 0, projection_definition)
      block_data%terrain = 7.5_fp

      ! Read-only external inputs may use dataset-native dimension names.
      write (filename, '(A,I0,A)') '/tmp/flexctm-test-wrf-input-', storage_size(0._fp), '.nc'
      if (proc%is_root()) then
         call check_netcdf(nf90_create(filename, nf90_clobber, ncid), 'creating WRF-like test input', filename)
         call check_netcdf(nf90_def_dim(ncid, 'west_east', 4, dimid), 'defining west_east', filename)
         call check_netcdf(nf90_def_dim(ncid, 'south_north', 4, dimid), 'defining south_north', filename)
         call check_netcdf(nf90_def_dim(ncid, 'bottom_top', 2, dimid), 'defining bottom_top', filename)
         call check_netcdf(nf90_enddef(ncid), 'ending WRF-like define mode', filename)
         call check_netcdf(nf90_close(ncid), 'closing WRF-like test input', filename)
      end if
      call MPI_Barrier(proc%model%comm, status)
      fh = open_nc_file(proc, proc%domains(1), proc%tiles(1), filename, is_read=.true.)
      call close_nc_file(fh)
      call delete_output(proc, filename)

      write (filename, '(A,I0,A)') '/tmp/flexctm-test-static-', storage_size(0._fp), '.nc'
      call write_static_output(proc, proc%domains(1), proc%tiles(1), block_data, filename, 0, 115._fp, 30._fp, 20._fp, 40._fp)

      status = nf90_open(filename, nf90_nowrite, ncid)
      call check(error, status == nf90_noerr, 'NetCDF file cannot be reopened')
      if (.not. allocated(error)) then
         status = nf90_inq_varid(ncid, 'terrain', varid)
         call check(error, status == nf90_noerr, 'NetCDF variable is missing')
      end if
      if (.not. allocated(error)) then
         status = nf90_inquire_variable(ncid, varid, xtype=xtype)
         call check(error, status == nf90_noerr .and. xtype == model_netcdf_type, 'NetCDF variable has the wrong storage type')
      end if
      if (.not. allocated(error)) then
         status = nf90_get_var(ncid, varid, readback)
         call check(error, status == nf90_noerr .and. all(abs(readback - 7.5_fp) <= epsilon(1._fp)), &
                    'NetCDF round trip changed field values')
      end if
      if (.not. allocated(error)) then
         status = nf90_get_att(ncid, nf90_global, 'proj_id', projection_id)
         call check(error, status == nf90_noerr .and. projection_id == 0, 'static output projection metadata is invalid')
      end if
      if (.not. allocated(error)) then
         status = nf90_get_att(ncid, nf90_global, 'ref_lon', projection_longitude)
         call check(error, status == nf90_noerr .and. abs(projection_longitude - 115._fp) <= epsilon(1._fp), &
                    'static output projection longitude is invalid')
      end if
      status = nf90_close(ncid)

      call delete_output(proc, filename)

      write (filename, '(A,I0,A)') '/tmp/flexctm-test-model-', storage_size(0._fp), '.nc'
      block_data%mete_table%var2ds(1)%output = .false.
      disabled_name = block_data%mete_table%var2ds(1)%name
      block_data%chem3d = 3._fp
      block_data%mete2d = 4._fp
      block_data%mete3d = 5._fp

      call write_model_output(proc, proc%domains(1), proc%tiles(1), block_data, filename)

      status = nf90_open(filename, nf90_nowrite, ncid)
      call check(error, status == nf90_noerr, 'model output cannot be reopened')
      if (.not. allocated(error)) then
         status = nf90_inq_varid(ncid, 'O3', varid)
         call check(error, status == nf90_noerr, 'chemical output variable is missing')
      end if
      if (.not. allocated(error)) then
         status = nf90_inq_varid(ncid, 'U', varid)
         call check(error, status == nf90_noerr, 'meteorology output variable is missing')
      end if
      if (.not. allocated(error)) then
         status = nf90_inq_varid(ncid, trim(disabled_name), varid)
         call check(error, status /= nf90_noerr, 'output=false meteorology variable was written')
      end if
      status = nf90_close(ncid)
      call delete_output(proc, filename)

      call block_data%clear()
      call proc%clear()
   end subroutine test_outputs

   subroutine delete_output(proc, filename)
      type(process_type), intent(in) :: proc
      character(len=*), intent(in) :: filename
      integer :: unit, status, mpi_status

      call MPI_Barrier(proc%model%comm, mpi_status)
      if (proc%is_root()) then
         open (newunit=unit, file=filename, status='old', iostat=status)
         if (status == 0) close (unit, status='delete')
      end if
      call MPI_Barrier(proc%model%comm, mpi_status)
   end subroutine delete_output
end module test_integration_netcdf

program tester
   use, intrinsic :: iso_fortran_env, only: error_unit
   use testdrive, only: run_testsuite
   use test_integration_netcdf, only: collect_tests
   implicit none
   integer :: stat
   stat = 0
   call run_testsuite(collect_tests, error_unit, stat)
   if (stat > 0) error stop 'output integration tests failed'
end program tester
