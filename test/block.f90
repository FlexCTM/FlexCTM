module test_block
   use mod_block, only: block_type
   use mod_chem_type, only: chem_table_type
   use mod_chem_csv, only: load_chem_table
   use mod_mete_type, only: mete_table_type
   use mod_mete_csv, only: load_mete_table
   use parallel, only: grid_meta_type, process_type
   use testdrive, only: check, error_type, new_unittest, unittest_type
   implicit none
   private
   public :: collect_tests
contains
   subroutine collect_tests(tests)
      type(unittest_type), allocatable, intent(out) :: tests(:)
      tests = [new_unittest('block allocation and clear', test_allocation)]
   end subroutine collect_tests

   subroutine setup(block_data, proc)
      type(block_type), intent(out) :: block_data
      type(process_type), intent(out) :: proc
      type(chem_table_type) :: chemistry
      type(mete_table_type) :: meteorology
      type(grid_meta_type) :: grid(1)
      chemistry = load_chem_table('meta/species.csv')
      meteorology = load_mete_table('meta/mete.standard.csv')
      call grid(1)%init(1, 4, 3, 2, parent_id=0)
      call proc%init(grid, 1, chemistry%nvar, is_global=.false.)
      call block_data%init(proc%bridges(1), proc%tiles(1), 2, 1, chemistry, meteorology, 1)
   end subroutine setup

   subroutine test_allocation(error)
      type(error_type), allocatable, intent(out) :: error
      type(block_type) :: block_data
      type(process_type) :: proc
      call setup(block_data, proc)
      call check(error, all(shape(block_data%mete2d) == [6, 5, 8]), &
                 'two-dimensional meteorology has the wrong shape')
      if (.not. allocated(error)) &
         call check(error, all(shape(block_data%mete3d) == [6, 5, 2, 14]), &
                    'three-dimensional meteorology has the wrong shape')
      if (.not. allocated(error)) &
         call check(error, all(block_data%mete2d == 0) .and. all(block_data%mete3d == 0), &
                    'meteorology arrays were not initialized')
      if (.not. allocated(error)) &
         call check(error, associated(block_data%rho) .and. associated(block_data%kz) .and. &
                           allocated(block_data%rho_next), &
                    'meteorology aliases or rho_next were not initialized')
      call block_data%clear()
      if (.not. allocated(error)) &
         call check(error, .not. allocated(block_data%mete2d) .and. &
                           .not. allocated(block_data%mete3d) .and. &
                           .not. allocated(block_data%rho_next), &
                    'block clear did not release meteorology arrays')
      call proc%clear()
   end subroutine test_allocation
end module test_block

program tester
   use, intrinsic :: iso_fortran_env, only: error_unit
   use testdrive, only: run_testsuite
   use test_block, only: collect_tests
   implicit none
   integer :: stat
   stat = 0
   call run_testsuite(collect_tests, error_unit, stat)
   if (stat > 0) error stop 'block tests failed'
end program tester
