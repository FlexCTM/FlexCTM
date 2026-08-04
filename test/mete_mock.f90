module test_mete_mock
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use mod_const, only: fp, P00, Rd
   use mod_block, only: block_type
   use mod_chem_type, only: chem_table_type
   use mod_chem_csv, only: load_chem_table
   use mod_mete_type, only: mete_table_type
   use mod_mete_csv, only: load_mete_table
   use mod_meteorology_mock, only: generate_mock_meteorology, generate_mock_static
   use parallel, only: grid_meta_type, process_type
   use projection, only: proj_type
   use testdrive, only: check, error_type, new_unittest, unittest_type
   implicit none
   private
   public :: collect_tests
contains
   subroutine collect_tests(tests)
      type(unittest_type), allocatable, intent(out) :: tests(:)
      tests = [new_unittest('MOCK meteorology interface', test_fields)]
   end subroutine collect_tests

   subroutine setup(block_data, proc)
      type(block_type), intent(out) :: block_data
      type(process_type), intent(out) :: proc
      type(chem_table_type) :: chemistry
      type(mete_table_type) :: table
      type(grid_meta_type) :: grid(1)
      chemistry = load_chem_table('meta/species.csv')
      table = load_mete_table('meta/mete.standard.csv')
      call grid(1)%init(1, 3, 2, 3, parent_id=0)
      call proc%init(grid, 1, chemistry%nvar, is_global=.false.)
      call block_data%init(proc%bridges(1), proc%tiles(1), 3, 1, chemistry, table, 1)
   end subroutine setup

   subroutine test_fields(error)
      type(error_type), allocatable, intent(out) :: error
      type(block_type) :: block_data
      type(process_type) :: proc
      type(proj_type) :: projection_definition
      real(fp), allocatable :: snapshot(:, :, :, :)
      real(fp) :: tolerance
      call setup(block_data, proc)
      call block_data%mesh%init(-30._fp, -60._fp, 30._fp, &
                                block_data%nx, block_data%ny, 0, projection_definition)
      call generate_mock_static(block_data)
      call generate_mock_meteorology(block_data)
      tolerance = 100._fp*epsilon(1._fp)
      call check(error, maxval(block_data%u) > minval(block_data%u) .and. &
                        maxval(block_data%v) > minval(block_data%v) .and. &
                        all(block_data%w == 0._fp), 'MOCK winds lack meaningful latitude structure')
      if (.not. allocated(error)) &
         call check(error, all(block_data%dz == 500._fp) .and. &
                           all(block_data%zt(:, :, 2) == 1000._fp), 'MOCK vertical grid is incorrect')
      if (.not. allocated(error)) &
         call check(error, all(block_data%P(:, :, 2) < block_data%P(:, :, 1)) .and. &
                           all(block_data%T(:, :, 2) < block_data%T(:, :, 1)), &
                    'MOCK pressure or temperature is not monotonic')
      if (.not. allocated(error)) &
         call check(error, maxval(abs(block_data%rho - block_data%P/(Rd*block_data%T))) <= tolerance, &
                    'MOCK density violates the ideal-gas equation')
      if (.not. allocated(error)) &
         call check(error, all(ieee_is_finite(block_data%mete3d)) .and. &
                           all(block_data%PSFC <= P00) .and. maxval(block_data%terrain) > 0._fp, &
                    'MOCK fields are not finite or static values are wrong')
      if (.not. allocated(error)) snapshot = block_data%mete3d
      if (.not. allocated(error)) block_data%mete3d = -999._fp
      if (.not. allocated(error)) call generate_mock_meteorology(block_data)
      if (.not. allocated(error)) &
         call check(error, &
                    all(block_data%u == snapshot(:, :, :, block_data%m3d_idx%get('U'))) .and. &
                    all(block_data%rho == snapshot(:, :, :, block_data%m3d_idx%get('rho'))), &
                    'MOCK standard-field generation is not deterministic')
      if (.not. allocated(error)) &
         call check(error, all(block_data%volume == -999._fp), &
                    'MOCK generation modified a common diagnostic field')
      call block_data%clear()
      call proc%clear()
   end subroutine test_fields
end module test_mete_mock

program tester
   use, intrinsic :: iso_fortran_env, only: error_unit
   use testdrive, only: run_testsuite
   use test_mete_mock, only: collect_tests
   implicit none
   integer :: stat
   stat = 0
   call run_testsuite(collect_tests, error_unit, stat)
   if (stat > 0) error stop 'MOCK meteorology tests failed'
end program tester
