module test_mete_diagnostic
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use mod_const, only: fp
   use mod_block, only: block_type
   use mod_chem_type, only: chem_table_type
   use mod_chem_csv, only: load_chem_table
   use mod_mete_type, only: mete_table_type
   use mod_mete_csv, only: load_mete_table
   use mod_meteorology_mock, only: generate_mock_meteorology
   use mod_mete_diagnostic, only: diagnose_meteorology
   use parallel, only: grid_meta_type, process_type
   use projection, only: proj_type
   use testdrive, only: check, error_type, new_unittest, unittest_type
   implicit none
   private
   public :: collect_tests
contains
   subroutine collect_tests(tests)
      type(unittest_type), allocatable, intent(out) :: tests(:)
      tests = [new_unittest('common meteorology diagnostics', test_diagnostics)]
   end subroutine collect_tests

   subroutine setup(block_data, proc)
      type(block_type), intent(out) :: block_data
      type(process_type), intent(out) :: proc
      type(chem_table_type) :: chemistry
      type(mete_table_type) :: table
      type(grid_meta_type) :: grid(1)
      type(proj_type) :: projection_definition
      chemistry = load_chem_table('meta/species.csv')
      table = load_mete_table('meta/mete.standard.csv')
      call grid(1)%init(1, 4, 4, 3, parent_id=0)
      call proc%init(grid, 1, chemistry%nvar, is_global=.false.)
      call block_data%init(proc%bridges(1), proc%tiles(1), 3, 1, chemistry, table, 1)
      call block_data%mesh%init(0._fp, 0._fp, 1._fp, block_data%nx, block_data%ny, 0, projection_definition)
      call generate_mock_meteorology(block_data)
   end subroutine setup

   subroutine test_diagnostics(error)
      type(error_type), allocatable, intent(out) :: error
      type(block_type) :: block_data
      type(process_type) :: proc
      real(fp), allocatable :: pressure(:, :, :), temperature(:, :, :), density(:, :, :)
      integer :: k
      call setup(block_data, proc)
      pressure = block_data%P
      temperature = block_data%T
      density = block_data%rho
      call diagnose_meteorology(proc%tiles(1), block_data, 60._fp)
      do k = 1, block_data%nz
         call check(error, all(block_data%volume(:, :, k) == block_data%mesh%area*block_data%dz(:, :, k)), &
                    'cell volume does not equal area times thickness')
         if (allocated(error)) exit
      end do
      if (.not. allocated(error)) call check(error, all(ieee_is_finite(block_data%kx)) .and. &
                           all(ieee_is_finite(block_data%ky)) .and. all(ieee_is_finite(block_data%kz)), &
                    'diffusivities are not finite')
      if (.not. allocated(error)) call check(error, all(block_data%kx >= 0._fp) .and. all(block_data%ky >= 0._fp) .and. &
                           all(block_data%kz >= 0._fp), 'diagnosed diffusivity is negative')
      if (.not. allocated(error)) call check(error, all(ieee_is_finite(block_data%Ri)) .and. &
                           all(ieee_is_finite(block_data%ustar)) .and. &
                           all(block_data%ustar >= 0._fp), 'surface-layer diagnostics are invalid')
      if (.not. allocated(error)) call check(error, all(block_data%P == pressure) .and. all(block_data%T == temperature) .and. &
                           all(block_data%rho == density), 'common diagnostics modified standard fields')
      call block_data%clear()
      call proc%clear()
   end subroutine test_diagnostics
end module test_mete_diagnostic

program tester
   use, intrinsic :: iso_fortran_env, only: error_unit
   use testdrive, only: run_testsuite
   use test_mete_diagnostic, only: collect_tests
   implicit none
   integer :: stat
   stat = 0
   call run_testsuite(collect_tests, error_unit, stat)
   if (stat > 0) error stop 'meteorology diagnostic tests failed'
end program tester
