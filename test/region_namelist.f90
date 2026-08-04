module test_region_namelist
   use mod_namelist, only: config_type, load_config
   use testdrive, only: check, error_type, new_unittest, unittest_type
   implicit none
   private
   public :: collect_tests
contains
   subroutine collect_tests(tests)
      type(unittest_type), allocatable, intent(out) :: tests(:)
      tests = [new_unittest('formal regional configuration', test_config)]
   end subroutine collect_tests

   subroutine test_config(error)
      type(error_type), allocatable, intent(out) :: error
      type(config_type) :: config
      config = load_config('region.nml')
      call check(error, config%we(1) == 88 .and. config%sn(1) == 77 .and. &
                        config%nlev == 29 .and. config%proj_id == 1, &
                 'formal regional grid changed unexpectedly')
      if (.not. allocated(error)) &
         call check(error, trim(config%bc_file) == './icbc/naqp_bc.nc' .and. &
                           trim(config%ic_file) == './icbc/naqp_ic_d0[DOMAIN].nc', &
                    'formal regional initial or boundary configuration changed')
      if (.not. allocated(error)) &
         call check(error, index(config%mete_file, '/3clear/share/xiaolh/v3/region/wrf/') == 1 .and. &
                           index(config%emis_file, '/3clear/share/xiaolh/v3/region/emis/') == 1, &
                    'formal regional input paths changed unexpectedly')
   end subroutine test_config
end module test_region_namelist

program tester
   use, intrinsic :: iso_fortran_env, only: error_unit
   use testdrive, only: run_testsuite
   use test_region_namelist, only: collect_tests
   implicit none
   integer :: stat
   stat = 0
   call run_testsuite(collect_tests, error_unit, stat)
   if (stat > 0) error stop 'formal regional configuration tests failed'
end program tester
