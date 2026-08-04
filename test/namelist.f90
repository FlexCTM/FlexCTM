module test_namelist
   use mod_const, only: fp
   use mod_namelist, only: calculate_time_steps
   use projection, only: create_proj, PROJ_ERR_CODE
   use testdrive, only: check, error_type, new_unittest, unittest_type
   implicit none
   private
   public :: collect_tests
contains
   subroutine collect_tests(tests)
      type(unittest_type), allocatable, intent(out) :: tests(:)
      tests = [new_unittest('integral run duration', test_integral), &
               new_unittest('nonintegral run duration', test_nonintegral), &
               new_unittest('invalid projection code', test_projection)]
   end subroutine collect_tests
   subroutine test_integral(error)
      type(error_type), allocatable, intent(out) :: error
      integer :: steps, stat
      character(128) :: message
      call calculate_time_steps(60._fp, 900._fp, steps, stat, message)
      call check(error, stat == 0 .and. steps == 4, 'one hour at 900 s must produce four steps')
   end subroutine test_integral
   subroutine test_nonintegral(error)
      type(error_type), allocatable, intent(out) :: error
      integer :: steps, stat
      character(128) :: message
      call calculate_time_steps(10._fp, 420._fp, steps, stat, message)
      call check(error, stat /= 0 .and. len_trim(message) > 0, 'nonintegral duration was accepted')
   end subroutine test_nonintegral
   subroutine test_projection(error)
      type(error_type), allocatable, intent(out) :: error
      integer :: stat
      character(:), allocatable :: message
      block
         use projection, only: proj_type
         type(proj_type) :: map
         map = create_proj(-1, stat=stat, errmsg=message)
      end block
      call check(error, stat == PROJ_ERR_CODE .and. len(message) > 0, &
                 'invalid projection did not return a diagnostic')
   end subroutine test_projection
end module test_namelist

program tester
   use, intrinsic :: iso_fortran_env, only: error_unit
   use testdrive, only: run_testsuite
   use test_namelist, only: collect_tests
   implicit none
   integer :: stat
   stat = 0
   call run_testsuite(collect_tests, error_unit, stat)
   if (stat > 0) error stop 'namelist tests failed'
end program tester
