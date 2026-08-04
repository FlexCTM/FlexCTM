module mod_chem_csv
   !! FlexCTM 化学变量 CSV 的读取与一致性校验。
   use, intrinsic :: iso_fortran_env, only: iostat_end
   use mod_chem_type, only: CHEM_REACTIVE, CHEM_PASSIVE, CHEM_DIAGNOSTIC
   use mod_chem_type, only: chem_species_type, chem_table_type
   use mod_error, only: fatal_error
   implicit none
   private
   public :: load_chem_table
contains

   function load_chem_table(filename) result(table)
      character(len=*), intent(in) :: filename
      type(chem_table_type) :: table
      character(len=1024) :: line, iomsg
      character(len=128) :: columns(16)
      integer :: unit, stat, row
      logical :: exists

      inquire (file=filename, exist=exists)
      if (.not. exists) call fatal_error('chemical species CSV does not exist: "'//trim(filename)//'"')
      open (newunit=unit, file=filename, status='old', action='read', iostat=stat, iomsg=iomsg)
      if (stat /= 0) call fatal_error('cannot open chemical species CSV "'//trim(filename)//'": '//trim(iomsg))
      do
         read (unit, '(A)', iostat=stat, iomsg=iomsg) line
         if (stat == iostat_end) exit
         if (stat /= 0) call fatal_error('cannot read chemical species CSV "'//trim(filename)//'": '//trim(iomsg))
         if (.not. skip_line(line)) table%nvar = table%nvar + 1
      end do
      if (table%nvar == 0) call fatal_error('chemical species CSV is empty: "'//trim(filename)//'"')
      allocate (table%vars(table%nvar))
      rewind (unit)
      row = 0
      do
         read (unit, '(A)', iostat=stat, iomsg=iomsg) line
         if (stat == iostat_end) exit
         if (stat /= 0) call fatal_error('cannot read chemical species CSV "'//trim(filename)//'": '//trim(iomsg))
         if (skip_line(line)) cycle
         row = row + 1
         call split_csv(line, columns, filename)
         call parse_species(columns, table%vars(row), filename)
      end do
      close (unit)
      call finalize_table(table, filename)
   end function load_chem_table

   logical function skip_line(line)
      character(len=*), intent(in) :: line
      character(len=:), allocatable :: text
      text = adjustl(line)
      skip_line = len_trim(text) == 0 .or. text(1:1) == '!' .or. text(1:1) == '#'
      if (.not. skip_line) skip_line = index(text, 'name,') == 1
   end function skip_line

   subroutine split_csv(line, columns, filename)
      character(len=*), intent(in) :: line, filename
      character(len=*), intent(out) :: columns(:)
      integer :: i, start, comma
      columns = ''
      start = 1
      do i = 1, size(columns) - 1
         comma = index(line(start:), ',')
         if (comma == 0) call fatal_error('not enough columns in chemical species CSV "'//trim(filename)//'"')
         columns(i) = trim(adjustl(line(start:start + comma - 2)))
         start = start + comma
      end do
      columns(size(columns)) = trim(adjustl(line(start:)))
      if (index(columns(size(columns)), ',') > 0) &
         call fatal_error('too many columns in chemical species CSV "'//trim(filename)//'"')
   end subroutine split_csv

   subroutine parse_species(columns, species, filename)
      character(len=*), intent(in) :: columns(16), filename
      type(chem_species_type), intent(out) :: species
      integer :: stat
      species%name = columns(1)
      species%phase = columns(2)
      select case (trim(columns(3)))
      case ('reactive'); species%role = CHEM_REACTIVE
      case ('passive'); species%role = CHEM_PASSIVE
      case ('diagnostic'); species%role = CHEM_DIAGNOSTIC
      case default
         call fatal_error('unknown chemical role "'//trim(columns(3))//'" in "'//trim(filename)//'"')
      end select
      call parse_logical(columns(4), species%transported, species%name)
      call parse_logical(columns(5), species%advected, species%name)
      call parse_logical(columns(6), species%diffused, species%name)
      call parse_logical(columns(7), species%read_initial, species%name)
      call parse_logical(columns(8), species%read_boundary, species%name)
      call parse_logical(columns(9), species%read_emission, species%name)
      call parse_logical(columns(10), species%use_chemistry, species%name)
      call parse_logical(columns(11), species%dry_deposition, species%name)
      call parse_logical(columns(12), species%wet_deposition, species%name)
      call parse_logical(columns(13), species%write_output, species%name)
      species%unit = columns(14)
      read (columns(15), *, iostat=stat) species%molar_mass
      if (stat /= 0 .or. species%molar_mass < 0) &
         call fatal_error('invalid molar mass for chemical variable "'//trim(species%name)//'"')
      species%description = columns(16)
   end subroutine parse_species

   subroutine parse_logical(text, value, name)
      character(len=*), intent(in) :: text, name
      logical, intent(out) :: value
      select case (trim(text))
      case ('true'); value = .true.
      case ('false'); value = .false.
      case default
         call fatal_error('logical value for chemical variable "'//trim(name)//'" must be true or false')
      end select
   end subroutine parse_logical

   subroutine finalize_table(table, filename)
      type(chem_table_type), intent(inout) :: table
      character(len=*), intent(in) :: filename
      integer :: i, j, it, ir, ie, io
      do i = 1, table%nvar
         if (len_trim(table%vars(i)%name) == 0) call fatal_error('empty chemical variable name')
         do j = 1, i - 1
            if (trim(table%vars(i)%name) == trim(table%vars(j)%name)) call fatal_error('duplicate chemical variable "'// &
                                trim(table%vars(i)%name)//'" in "'//trim(filename)//'"')
         end do
         select case (trim(table%vars(i)%phase))
         case ('gas'); table%ngas = table%ngas + 1
         case ('aerosol'); table%naerosol = table%naerosol + 1
         case ('diagnostic')
         case default
            call fatal_error('unknown phase for chemical variable "'//trim(table%vars(i)%name)//'"')
         end select
         if ((table%vars(i)%advected .or. table%vars(i)%diffused) .and. .not. table%vars(i)%transported) &
            call fatal_error('non-transported variable cannot be advected or diffused: "'// trim(table%vars(i)%name)//'"')
         if (table%vars(i)%use_chemistry .and. table%vars(i)%role /= CHEM_REACTIVE) &
            call fatal_error('chemistry variable must have reactive role: "'//trim(table%vars(i)%name)//'"')
         if (table%vars(i)%transported) table%ntransported = table%ntransported + 1
         if (table%vars(i)%use_chemistry) table%nreactive = table%nreactive + 1
         if (table%vars(i)%read_emission) table%nemission = table%nemission + 1
         if (table%vars(i)%write_output) table%noutput = table%noutput + 1
      end do
      allocate (table%transported_indices(table%ntransported), table%reactive_indices(table%nreactive), &
                table%emission_indices(table%nemission), table%output_indices(table%noutput))
      it = 0; ir = 0; ie = 0; io = 0
      do i = 1, table%nvar
         if (table%vars(i)%transported) then; it = it + 1; table%transported_indices(it) = i; end if
         if (table%vars(i)%use_chemistry) then; ir = ir + 1; table%reactive_indices(ir) = i; end if
         if (table%vars(i)%read_emission) then; ie = ie + 1; table%emission_indices(ie) = i; end if
         if (table%vars(i)%write_output) then; io = io + 1; table%output_indices(io) = i; end if
      end do
   end subroutine finalize_table

end module mod_chem_csv
