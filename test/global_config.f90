module test_global_config
   use mod_const, only: fp
   use mod_namelist, only: config_type, load_config
   use testdrive, only: check, error_type, new_unittest, unittest_type
   implicit none
   private
   public :: collect_tests
contains
   subroutine collect_tests(tests)
      type(unittest_type), allocatable, intent(out) :: tests(:)
      tests = [new_unittest('one-degree global MOCK configuration', test_config)]
   end subroutine collect_tests

   subroutine test_config(error)
      type(error_type), allocatable, intent(out) :: error
      type(config_type) :: config
      config = load_config('global_mock.nml')
      call check(error, config%ndom == 1 .and. config%we(1) == 360 .and. &
                        config%sn(1) == 180 .and. config%nlev == 20, &
                 'global MOCK grid dimensions are incorrect')
      if (.not. allocated(error)) &
         call check(error, config%proj_id == 0 .and. config%is_global .and. &
                           abs(config%delta - 1._fp) <= epsilon(1._fp) .and. &
                           abs(config%xorgs(1) + 180._fp) <= epsilon(1._fp), &
                    'global MOCK projection is not a one-degree global grid')
      if (.not. allocated(error)) &
         call check(error, trim(config%mete_source) == 'mock' .and. &
                           len_trim(config%ic_file) == 0 .and. &
                           len_trim(config%bc_file) == 0 .and. &
                           len_trim(config%emis_file) == 0, &
                    'global MOCK input paths are not configured consistently')
      if (.not. allocated(error)) &
         call check(error, config%nt == 12 .and. abs(config%dts(1) - 600._fp) <= epsilon(1._fp), &
                    'global MOCK duration does not produce exactly twelve configured time steps')
   end subroutine test_config
end module test_global_config

program tester
   use, intrinsic :: iso_fortran_env, only: error_unit
   use testdrive, only: run_testsuite
   use test_global_config, only: collect_tests
   implicit none
   integer :: stat
   stat = 0
   call run_testsuite(collect_tests, error_unit, stat)
   if (stat > 0) error stop 'global configuration tests failed'
end program tester
