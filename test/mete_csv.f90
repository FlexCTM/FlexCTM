module test_mete_csv
   use mod_mete_type, only: METE_STANDARD, METE_DIAGNOSTIC
   use mod_mete_type, only: mete_table_type, mete_mapping_table_type
   use mod_mete_csv, only: load_mete_table, load_mete_mapping_table, validate_mete_mapping
   use testdrive, only: check, error_type, new_unittest, unittest_type
   implicit none
   private
   public :: collect_tests
contains
   subroutine collect_tests(tests)
      type(unittest_type), allocatable, intent(out) :: tests(:)
      tests = [new_unittest('standard table parsing', test_standard), &
               new_unittest('output flag parsing', test_output_flags), &
               new_unittest('WRF mapping parsing', test_mapping), &
               new_unittest('table and mapping compatibility', test_compatibility), &
               new_unittest('mapping dimension mismatch', test_dimension_mismatch), &
               new_unittest('mapping dependency order', test_dependency_order)]
   end subroutine collect_tests

   subroutine test_standard(error)
      type(error_type), allocatable, intent(out) :: error
      type(mete_table_type) :: table
      table = load_mete_table('meta/mete.standard.csv')
      call check(error, table%n_2d == 8 .and. table%n_3d == 14, 'wrong field counts')
      if (allocated(error)) return
      call check(error, table%n_standard_2d == 4 .and. table%n_standard_3d == 9, &
                 'wrong standard-field counts')
      if (allocated(error)) return
      call check(error, table%n_diagnostic_2d == 4 .and. table%n_diagnostic_3d == 5, &
                 'wrong diagnostic-field counts')
      if (allocated(error)) return
      call check(error, table%var3ds(table%idx('rho'))%category == METE_STANDARD .and. &
                        table%var3ds(table%idx('kz'))%category == METE_DIAGNOSTIC .and. &
                        table%var3ds(table%idx('rho'))%output, &
                 'field categories or output flags were parsed incorrectly')
   end subroutine test_standard

   subroutine test_output_flags(error)
      type(error_type), allocatable, intent(out) :: error
      type(mete_table_type) :: table
      character(len=*), parameter :: filename = '/tmp/flexctm-mete-output-flags.csv'
      integer :: unit

      open (newunit=unit, file=filename, status='replace', action='write')
      write (unit, '(A)') 'enabled,2,standard,true,1,enabled field'
      write (unit, '(A)') 'disabled,2,diagnostic,false,1,disabled field'
      close (unit)

      table = load_mete_table(filename)
      call check(error, table%var2ds(table%idx('enabled'))%output .and. &
                        .not. table%var2ds(table%idx('disabled'))%output, &
                 'true/false output flags were parsed incorrectly')

      open (newunit=unit, file=filename, status='old')
      close (unit, status='delete')
   end subroutine test_output_flags

   subroutine test_mapping(error)
      type(error_type), allocatable, intent(out) :: error
      type(mete_mapping_table_type) :: mapping
      integer :: index
      mapping = load_mete_mapping_table('meta/mete.wrf.csv')
      call check(error, mapping%nvar == 13, 'wrong WRF mapping count')
      if (allocated(error)) return
      index = mapping%idx('T')
      call check(error, size(mapping%vars(index)%inputs) == 3 .and. &
                        trim(mapping%vars(index)%method) == 'wrf_air_temperature', &
                 'WRF temperature mapping was parsed incorrectly')
   end subroutine test_mapping

   subroutine test_compatibility(error)
      type(error_type), allocatable, intent(out) :: error
      type(mete_table_type) :: table
      type(mete_mapping_table_type) :: mapping
      character(:), allocatable :: message
      integer :: stat
      table = load_mete_table('meta/mete.standard.csv')
      mapping = load_mete_mapping_table('meta/mete.wrf.csv')
      call validate_mete_mapping(table, mapping, stat, message)
      call check(error, stat == 0 .and. len(message) == 0, 'valid tables were rejected')
      if (allocated(error)) return
      mapping%vars(mapping%idx('P'))%target_unit = 'hPa'
      call validate_mete_mapping(table, mapping, stat, message)
      call check(error, stat /= 0 .and. index(message, 'unit mismatch') > 0, &
                 'unit mismatch was not rejected')
   end subroutine test_compatibility

   subroutine test_dimension_mismatch(error)
      type(error_type), allocatable, intent(out) :: error
      type(mete_table_type) :: table
      type(mete_mapping_table_type) :: mapping
      character(:), allocatable :: message
      integer :: stat
      table = load_mete_table('meta/mete.standard.csv')
      mapping = load_mete_mapping_table('meta/mete.wrf.csv')
      mapping%vars(mapping%idx('U'))%ndim = 2
      call validate_mete_mapping(table, mapping, stat, message)
      call check(error, stat /= 0 .and. index(message, 'dimension mismatch') > 0, &
                 'dimension mismatch was not rejected')
   end subroutine test_dimension_mismatch

   subroutine test_dependency_order(error)
      type(error_type), allocatable, intent(out) :: error
      type(mete_table_type) :: table
      type(mete_mapping_table_type) :: mapping
      character(:), allocatable :: message
      integer :: p_index, t_index, stat
      type(mete_mapping_table_type) :: reordered
      table = load_mete_table('meta/mete.standard.csv')
      mapping = load_mete_mapping_table('meta/mete.wrf.csv')
      reordered = mapping
      p_index = reordered%idx('P')
      t_index = reordered%idx('T')
      reordered%vars([p_index, t_index]) = mapping%vars([t_index, p_index])
      call validate_mete_mapping(table, reordered, stat, message)
      call check(error, stat /= 0 .and. index(message, 'must be generated before') > 0, &
                 'dependency order error was not rejected')
   end subroutine test_dependency_order
end module test_mete_csv

program tester
   use, intrinsic :: iso_fortran_env, only: error_unit
   use testdrive, only: run_testsuite
   use test_mete_csv, only: collect_tests
   implicit none
   integer :: stat
   stat = 0
   call run_testsuite(collect_tests, error_unit, stat)
   if (stat > 0) error stop 'meteorology CSV tests failed'
end program tester
