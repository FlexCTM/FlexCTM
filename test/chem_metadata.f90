module test_chem_metadata
   use mod_chem_type, only: chem_table_type
   use mod_chem_csv, only: load_chem_table
   use testdrive, only: check, error_type, new_unittest, unittest_type
   implicit none
   private
   public :: collect_tests, run_probe
contains
   subroutine collect_tests(tests)
      type(unittest_type), allocatable, intent(out) :: tests(:)
      tests = [new_unittest('valid chemical metadata', test_valid), &
               new_unittest('invalid chemical metadata', test_invalid)]
   end subroutine collect_tests

   subroutine test_valid(error)
      type(error_type), allocatable, intent(out) :: error
      type(chem_table_type) :: table
      table = load_chem_table('meta/species.csv')
      call check(error, table%nvar == 15 .and. table%ngas == 11 .and. &
                        table%naerosol == 3 .and. table%ntransported == 15, &
                 'chemical metadata counts are incorrect')
      if (allocated(error)) return
      call check(error, table%contain('rho') .and. table%idx('SO4') > 0, &
                 'chemical metadata lookup failed')
      if (allocated(error)) return
      associate (rho => table%vars(table%idx('rho')))
         call check(error, rho%transported .and. rho%advected .and. rho%diffused .and. &
                           .not. rho%read_emission .and. .not. rho%use_chemistry .and. &
                           .not. rho%dry_deposition .and. .not. rho%wet_deposition, &
                    'rho is not a diagnostic transported variable')
      end associate
      if (allocated(error)) return
      call check(error, table%nemission == 8 .and. table%nreactive == 14 .and. &
                        table%noutput == 12, 'chemical process index counts are incorrect')
   end subroutine test_valid

   subroutine test_invalid(error)
      type(error_type), allocatable, intent(out) :: error
      character(512) :: executable
      character(len=*), parameter :: path = '/tmp/flexctm-invalid-chem.csv'
      integer :: exit_status
      call get_command_argument(0, executable)
      call execute_probe(executable, path//'-missing', exit_status)
      call check(error, exit_status /= 0, 'missing metadata was accepted')
      if (allocated(error)) return
      call write_file(path, &
         'X,gas,unknown,true,true,true,false,false,false,false,false,false,false,ug m-3,1.0,bad role')
      call execute_probe(executable, path, exit_status)
      call check(error, exit_status /= 0, 'unknown chemical type was accepted')
      if (allocated(error)) return
      call write_file(path, &
         'X,gas,passive,true,true,true,false,false,false,false,false,false,false,ug m-3,1.0,first'// &
         new_line('a')// &
         'X,gas,passive,true,true,true,false,false,false,false,false,false,false,ug m-3,1.0,second')
      call execute_probe(executable, path, exit_status)
      call check(error, exit_status /= 0, 'duplicate chemical name was accepted')
      call delete_file(path)
   end subroutine test_invalid

   subroutine run_probe()
      character(512) :: path
      type(chem_table_type) :: table
      call get_command_argument(2, path)
      table = load_chem_table(trim(path))
   end subroutine run_probe

   subroutine execute_probe(executable, path, exit_status)
      character(len=*), intent(in) :: executable, path
      integer, intent(out) :: exit_status
      call execute_command_line(trim(executable)//' --probe '//trim(path), wait=.true., exitstat=exit_status)
   end subroutine execute_probe

   subroutine write_file(path, content)
      character(len=*), intent(in) :: path, content
      integer :: unit
      open (newunit=unit, file=path, status='replace', action='write')
      write (unit, '(a)') content
      close (unit)
   end subroutine write_file

   subroutine delete_file(path)
      character(len=*), intent(in) :: path
      integer :: unit, stat
      open (newunit=unit, file=path, status='old', iostat=stat)
      if (stat == 0) close (unit, status='delete')
   end subroutine delete_file
end module test_chem_metadata

program tester
   use, intrinsic :: iso_fortran_env, only: error_unit
   use testdrive, only: run_testsuite
   use test_chem_metadata, only: collect_tests, run_probe
   implicit none
   integer :: stat
   character(32) :: mode
   call get_command_argument(1, mode)
   if (trim(mode) == '--probe') then
      call run_probe()
      stop
   end if
   stat = 0
   call run_testsuite(collect_tests, error_unit, stat)
   if (stat > 0) error stop 'chemical metadata tests failed'
end program tester
