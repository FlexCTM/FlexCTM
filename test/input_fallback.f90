module test_input_fallback
   use mod_block, only: block_type
   use mod_chem_csv, only: load_chem_table
   use mod_chem_type, only: chem_table_type
   use mod_const, only: fp
   use mod_emission, only: update_emission
   use mod_initial, only: initialize_chemistry
   use mod_mete_csv, only: load_mete_table
   use mod_mete_type, only: mete_table_type
   use parallel, only: grid_meta_type, process_type
   use projection, only: proj_type
   use testdrive, only: check, error_type, new_unittest, unittest_type
   implicit none
   private
   public :: collect_tests
contains
   subroutine collect_tests(tests)
      type(unittest_type), allocatable, intent(out) :: tests(:)
      tests = [new_unittest('missing chemistry input fallbacks', test_fallbacks)]
   end subroutine collect_tests

   subroutine test_fallbacks(error)
      type(error_type), allocatable, intent(out) :: error
      type(block_type) :: block_data
      type(chem_table_type) :: chemistry
      type(mete_table_type) :: meteorology
      type(grid_meta_type) :: grid(1)
      type(process_type) :: proc
      type(proj_type) :: projection_definition
      integer :: ozone_index, carbon_monoxide_index

      chemistry = load_chem_table('meta/species.csv')
      meteorology = load_mete_table('meta/mete.standard.csv')
      call grid(1)%init(1, 8, 4, 3, parent_id=0)
      call proc%init(grid, 1, chemistry%nvar, is_global=.false.)
      call block_data%init(proc%bridges(1), proc%tiles(1), 3, 1, chemistry, meteorology, 1)
      call block_data%mesh%init(-180._fp, -90._fp, 45._fp, block_data%nx, block_data%ny, 0, projection_definition)

      call initialize_chemistry(proc, proc%domains(1), proc%tiles(1), block_data, '/tmp/flexctm-missing-initial-input.nc')
      call update_emission(proc, proc%domains(1), proc%tiles(1), block_data, '/tmp/flexctm-missing-emission-input.nc', 1)

      ozone_index = chemistry%idx('O3')
      carbon_monoxide_index = chemistry%idx('CO')
      call check(error, all(block_data%chem3d == 0._fp), 'missing initial file did not produce a zero field')
      if (.not. allocated(error)) call check(error, maxval(block_data%emis3d(:, :, 1, carbon_monoxide_index)) > 0._fp .and. &
                           all(block_data%emis3d(:, :, 2:, carbon_monoxide_index) == 0._fp), &
                    'fallback emissions are not confined to the surface layer')
      if (.not. allocated(error)) call check(error, all(block_data%emis3d(:, :, :, ozone_index) == 0._fp), &
                    'fallback emissions populated a species without an emission input')
      call block_data%clear()
      call proc%clear()
   end subroutine test_fallbacks
end module test_input_fallback

program tester
   use, intrinsic :: iso_fortran_env, only: error_unit
   use testdrive, only: run_testsuite
   use test_input_fallback, only: collect_tests
   implicit none
   integer :: stat
   stat = 0
   call run_testsuite(collect_tests, error_unit, stat)
   if (stat > 0) error stop 'input fallback tests failed'
end program tester
