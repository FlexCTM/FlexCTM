module test_meteorology_dispatch
   use mod_const, only: fp
   use mod_block, only: block_type
   use mod_chem_type, only: chem_table_type
   use mod_chem_csv, only: load_chem_table
   use mod_mete_type, only: mete_table_type
   use mod_mete_csv, only: load_mete_table
   use mod_meteorology, only: read_mete_field, read_mete_static
   use parallel, only: grid_meta_type, process_type
   use projection, only: proj_type
   use testdrive, only: check, error_type, new_unittest, unittest_type
   implicit none
   private
   public :: collect_tests
contains
   subroutine collect_tests(tests)
      type(unittest_type), allocatable, intent(out) :: tests(:)
      tests = [new_unittest('MOCK dispatch without files', test_mock_dispatch)]
   end subroutine collect_tests

   subroutine test_mock_dispatch(error)
      type(error_type), allocatable, intent(out) :: error
      type(block_type) :: block_data
      type(process_type) :: proc
      type(chem_table_type) :: chemistry
      type(mete_table_type) :: table
      type(grid_meta_type) :: grid(1)
      type(proj_type) :: projection_definition
      chemistry = load_chem_table('meta/species.csv')
      table = load_mete_table('meta/mete.standard.csv')
      call grid(1)%init(1, 2, 2, 2, parent_id=0)
      call proc%init(grid, 1, chemistry%nvar, is_global=.false.)
      call block_data%init(proc%bridges(1), proc%tiles(1), 2, 1, chemistry, table, 1)
      call block_data%mesh%init(-20._fp, -20._fp, 10._fp, &
                                block_data%nx, block_data%ny, 0, projection_definition)
      call read_mete_field('mock', proc, proc%domains(1), proc%tiles(1), block_data, &
                           '/tmp/this-file-must-not-exist.nc')
      call read_mete_static('mock', proc, proc%domains(1), proc%tiles(1), block_data, &
                            '/tmp/this-file-must-not-exist.nc')
      call check(error, all(block_data%u > 0._fp) .and. all(block_data%terrain >= 0._fp), &
                 'MOCK dispatch attempted file I/O or returned wrong values')
      call block_data%clear()
      call proc%clear()
   end subroutine test_mock_dispatch
end module test_meteorology_dispatch

program tester
   use, intrinsic :: iso_fortran_env, only: error_unit
   use testdrive, only: run_testsuite
   use test_meteorology_dispatch, only: collect_tests
   implicit none
   integer :: stat
   stat = 0
   call run_testsuite(collect_tests, error_unit, stat)
   if (stat > 0) error stop 'meteorology dispatch tests failed'
end program tester
