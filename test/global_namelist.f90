module test_global_namelist
   use mod_const, only: fp
   use mod_namelist, only: config_type, load_config
   use testdrive, only: check, error_type, new_unittest, unittest_type
   implicit none
   private
   public :: collect_tests
contains
   subroutine collect_tests(tests)
      type(unittest_type), allocatable, intent(out) :: tests(:)
      tests = [new_unittest('formal global configuration', test_config)]
   end subroutine collect_tests

   subroutine test_config(error)
      type(error_type), allocatable, intent(out) :: error
      type(config_type) :: config
      config = load_config('global.nml')
      call check(error, config%we(1) == 360 .and. config%sn(1) == 180 .and. &
                        config%nlev == 50 .and. abs(config%delta - 1._fp) <= epsilon(1._fp), &
                 'formal global grid changed unexpectedly')
      if (.not. allocated(error)) call check(error, trim(config%mete_source) == 'wrf', &
                    'formal global meteorology source is incorrect')
      if (.not. allocated(error)) call check(error, index(config%mete_file, '/3clear/share/xiaolh/v3/global/wrf/') == 1 .and. &
                           index(config%emis_file, '/3clear/share/xiaolh/v3/global/emis/') == 1, &
                    'formal global input paths changed unexpectedly')
      if (.not. allocated(error)) call check(error, trim(config%out_file) == 'ctm_d0[DOMAIN]_%Y%m%d%H.nc' .and. &
                           config%mete_steps == nint(config%mete_timedelta/config%dt) .and. &
                           config%output_steps == nint(config%output_timedelta/config%dt), &
                    'formal global output schedule is incorrect')
   end subroutine test_config
end module test_global_namelist

program tester
   use, intrinsic :: iso_fortran_env, only: error_unit
   use testdrive, only: run_testsuite
   use test_global_namelist, only: collect_tests
   implicit none
   integer :: stat
   stat = 0
   call run_testsuite(collect_tests, error_unit, stat)
   if (stat > 0) error stop 'formal global configuration tests failed'
end program tester
