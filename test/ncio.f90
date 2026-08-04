module test_ncio
   use mod_const, only: fp
   use mod_ncio, only: resolve_nc_open_options, model_netcdf_type
   use netcdf, only: NF90_DOUBLE, NF90_FLOAT
   use testdrive, only: check, error_type, new_unittest, unittest_type
   implicit none
   private
   public :: collect_tests
contains
   subroutine collect_tests(tests)
      type(unittest_type), allocatable, intent(out) :: tests(:)
      tests = [new_unittest('optional open modes', test_open_modes), &
               new_unittest('model NetCDF precision', test_precision)]
   end subroutine collect_tests

   subroutine test_open_modes(error)
      type(error_type), allocatable, intent(out) :: error
      logical :: existing, read_only
      call resolve_nc_open_options(open_existing=existing, read_only=read_only)
      call check_mode(error, existing, read_only, .false., .false.)
      if (allocated(error)) return
      call resolve_nc_open_options(is_old=.true., open_existing=existing, read_only=read_only)
      call check_mode(error, existing, read_only, .true., .false.)
      if (allocated(error)) return
      call resolve_nc_open_options(is_read=.true., open_existing=existing, read_only=read_only)
      call check_mode(error, existing, read_only, .true., .true.)
      if (allocated(error)) return
      call resolve_nc_open_options(is_old=.false., is_read=.true., &
                                   open_existing=existing, read_only=read_only)
      call check_mode(error, existing, read_only, .true., .true.)
   end subroutine test_open_modes

   subroutine check_mode(error, actual_existing, actual_read, expected_existing, expected_read)
      type(error_type), allocatable, intent(out) :: error
      logical, intent(in) :: actual_existing, actual_read, expected_existing, expected_read
      call check(error, actual_existing .eqv. expected_existing, 'wrong existing-file mode')
      if (allocated(error)) return
      call check(error, actual_read .eqv. expected_read, 'wrong read-only mode')
   end subroutine check_mode

   subroutine test_precision(error)
      type(error_type), allocatable, intent(out) :: error
      integer :: expected
      expected = merge(NF90_FLOAT, NF90_DOUBLE, storage_size(0._fp) == 32)
      call check(error, model_netcdf_type == expected, 'NetCDF storage type does not follow fp')
   end subroutine test_precision
end module test_ncio

program tester
   use, intrinsic :: iso_fortran_env, only: error_unit
   use testdrive, only: run_testsuite
   use test_ncio, only: collect_tests
   implicit none
   integer :: stat
   stat = 0
   call run_testsuite(collect_tests, error_unit, stat)
   if (stat > 0) error stop 'NetCDF option tests failed'
end program tester
