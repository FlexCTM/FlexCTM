module mod_mete_csv
   !! 标准气象变量表与数据集接口映射 CSV 的解析和交叉校验。
   use, intrinsic :: iso_fortran_env, only: iostat_end

   use mod_error, only: fatal_error
   use mod_mete_type, only: METE_STANDARD, METE_DIAGNOSTIC
   use mod_mete_type, only: METE_INPUT_RAW, METE_INPUT_STANDARD
   use mod_mete_type, only: mete_var_type, mete_table_type
   use mod_mete_type, only: mete_input_type, mete_mapping_table_type

   implicit none
   private

   public :: load_mete_table, load_mete_mapping_table
   public :: validate_mete_mapping

contains

   function load_mete_table(filename) result(table)
      character(len=*), intent(in) :: filename !! 标准变量 CSV 路径。
      type(mete_table_type) :: table

      character(len=512) :: line, iomsg
      character(len=128) :: columns(6)
      integer :: unit, stat, n_2d, n_3d, i_2d, i_3d

      call open_csv(filename, unit)
      call count_table_rows(unit, filename, n_2d, n_3d)
      allocate (table%var2ds(n_2d), table%var3ds(n_3d))
      table%n_2d = n_2d
      table%n_3d = n_3d

      rewind (unit, iostat=stat, iomsg=iomsg)
      if (stat /= 0) call fatal_error('cannot rewind meteorology table "'//trim(filename)//'": '//trim(iomsg))
      i_2d = 0
      i_3d = 0
      do
         read (unit, '(A)', iostat=stat, iomsg=iomsg) line
         if (stat == iostat_end) exit
         if (stat /= 0) call fatal_error('cannot read meteorology table "'//trim(filename)//'": '//trim(iomsg))
         if (skip_csv_line(line)) cycle
         call split_csv(line, columns, filename)
         if (trim(columns(2)) == '2') then
            i_2d = i_2d + 1
            call parse_mete_var(columns, table%var2ds(i_2d), filename)
         else
            i_3d = i_3d + 1
            call parse_mete_var(columns, table%var3ds(i_3d), filename)
         end if
      end do
      close (unit)
      call validate_mete_table(table, filename)
   end function load_mete_table

   function load_mete_mapping_table(filename) result(mapping)
      character(len=*), intent(in) :: filename !! 数据集映射 CSV 路径。
      type(mete_mapping_table_type) :: mapping

      character(len=512) :: line, iomsg
      character(len=128) :: columns(7)
      integer :: unit, stat, row

      call open_csv(filename, unit)
      mapping%nvar = count_csv_rows(unit, filename)
      allocate (mapping%vars(mapping%nvar))
      rewind (unit, iostat=stat, iomsg=iomsg)
      if (stat /= 0) call fatal_error('cannot rewind meteorology mapping "'//trim(filename)//'": '//trim(iomsg))

      row = 0
      do
         read (unit, '(A)', iostat=stat, iomsg=iomsg) line
         if (stat == iostat_end) exit
         if (stat /= 0) call fatal_error('cannot read meteorology mapping "'//trim(filename)//'": '//trim(iomsg))
         if (skip_csv_line(line)) cycle
         row = row + 1
         call split_csv(line, columns, filename)
         mapping%vars(row)%name = columns(1)
         read (columns(2), *, iostat=stat) mapping%vars(row)%ndim
         if (stat /= 0) call fatal_error('invalid mapping dimension for "'//trim(columns(1))//'"')
         call parse_inputs(columns(3), mapping%vars(row)%inputs, filename)
         mapping%vars(row)%method = columns(4)
         mapping%vars(row)%source_unit = columns(5)
         mapping%vars(row)%target_unit = columns(6)
         mapping%vars(row)%description = columns(7)
      end do
      close (unit)
      call validate_mapping_rows(mapping, filename)
   end function load_mete_mapping_table

   subroutine validate_mete_mapping(table, mapping, stat, errmsg)
      type(mete_table_type), intent(in) :: table
      type(mete_mapping_table_type), intent(in) :: mapping
      integer, optional, intent(out) :: stat
      character(:), allocatable, optional, intent(out) :: errmsg

      character(:), allocatable :: message
      integer :: i, j, index, ndim

      message = ''
      do i = 1, table%n_2d
         if (table%var2ds(i)%category == METE_STANDARD .and. .not. mapping%contain(table%var2ds(i)%name)) then
            message = 'missing mapping for standard variable "'//trim(table%var2ds(i)%name)//'"'
            exit
         end if
      end do
      if (len(message) == 0) then
         do i = 1, table%n_3d
            if (table%var3ds(i)%category == METE_STANDARD .and. .not. mapping%contain(table%var3ds(i)%name)) then
               message = 'missing mapping for standard variable "'//trim(table%var3ds(i)%name)//'"'
               exit
            end if
         end do
      end if

      if (len(message) == 0) then
         do i = 1, mapping%nvar
            index = table%idx(mapping%vars(i)%name, ndim)
            if (index == 0) then
               message = 'mapping target "'//trim(mapping%vars(i)%name)//'" is not defined'
               exit
            end if
            if (ndim /= mapping%vars(i)%ndim) then
               message = 'dimension mismatch for mapping target "'//trim(mapping%vars(i)%name)//'"'
               exit
            end if
            if (ndim == 2) then
               if (table%var2ds(index)%category /= METE_STANDARD) &
                  message = 'mapping target "'//trim(mapping%vars(i)%name)//'" is not a standard variable'
               if (trim(table%var2ds(index)%unit) /= trim(mapping%vars(i)%target_unit)) &
                  message = 'unit mismatch for mapping target "'//trim(mapping%vars(i)%name)//'"'
            else
               if (table%var3ds(index)%category /= METE_STANDARD) &
                  message = 'mapping target "'//trim(mapping%vars(i)%name)//'" is not a standard variable'
               if (trim(table%var3ds(index)%unit) /= trim(mapping%vars(i)%target_unit)) &
                  message = 'unit mismatch for mapping target "'//trim(mapping%vars(i)%name)//'"'
            end if
            if (len(message) > 0) exit
            do j = 1, size(mapping%vars(i)%inputs)
               if (mapping%vars(i)%inputs(j)%source == METE_INPUT_STANDARD .and. &
                   .not. mapping%contain(mapping%vars(i)%inputs(j)%name)) then
                  message = 'unknown standard dependency "'//trim(mapping%vars(i)%inputs(j)%name)//'"'
                  exit
               end if
               if (mapping%vars(i)%inputs(j)%source == METE_INPUT_STANDARD .and. &
                   mapping%idx(mapping%vars(i)%inputs(j)%name) >= i) then
                  message = 'standard dependency "'//trim(mapping%vars(i)%inputs(j)%name)// &
                            '" must be generated before "'//trim(mapping%vars(i)%name)//'"'
                  exit
               end if
            end do
            if (len(message) > 0) exit
         end do
      end if

      if (present(stat)) stat = merge(1, 0, len(message) > 0)
      if (present(errmsg)) errmsg = message
      if (.not. present(stat) .and. len(message) > 0) call fatal_error(message)
   end subroutine validate_mete_mapping

   subroutine open_csv(filename, unit)
      character(len=*), intent(in) :: filename
      integer, intent(out) :: unit
      character(len=512) :: iomsg
      integer :: stat
      logical :: exists

      inquire (file=filename, exist=exists)
      if (.not. exists) call fatal_error('CSV file does not exist: "'//trim(filename)//'"')
      open (newunit=unit, file=filename, status='old', action='read', iostat=stat, iomsg=iomsg)
      if (stat /= 0) call fatal_error('cannot open CSV file "'//trim(filename)//'": '//trim(iomsg))
   end subroutine open_csv

   subroutine count_table_rows(unit, filename, n_2d, n_3d)
      integer, intent(in) :: unit
      character(len=*), intent(in) :: filename
      integer, intent(out) :: n_2d, n_3d
      character(len=512) :: line, iomsg
      character(len=128) :: columns(6)
      integer :: stat

      n_2d = 0
      n_3d = 0
      do
         read (unit, '(A)', iostat=stat, iomsg=iomsg) line
         if (stat == iostat_end) exit
         if (stat /= 0) call fatal_error('cannot read meteorology table "'//trim(filename)//'": '//trim(iomsg))
         if (skip_csv_line(line)) cycle
         call split_csv(line, columns, filename)
         select case (trim(columns(2)))
         case ('2')
            n_2d = n_2d + 1
         case ('3')
            n_3d = n_3d + 1
         case default
            call fatal_error('meteorology variable "'//trim(columns(1))//'" must have dimension 2 or 3')
         end select
      end do
      if (n_2d + n_3d == 0) call fatal_error('meteorology table is empty: "'//trim(filename)//'"')
   end subroutine count_table_rows

   integer function count_csv_rows(unit, filename) result(rows)
      integer, intent(in) :: unit
      character(len=*), intent(in) :: filename
      character(len=512) :: line, iomsg
      integer :: stat

      rows = 0
      do
         read (unit, '(A)', iostat=stat, iomsg=iomsg) line
         if (stat == iostat_end) exit
         if (stat /= 0) call fatal_error('cannot read CSV file "'//trim(filename)//'": '//trim(iomsg))
         if (.not. skip_csv_line(line)) rows = rows + 1
      end do
      if (rows == 0) call fatal_error('CSV file is empty: "'//trim(filename)//'"')
   end function count_csv_rows

   subroutine parse_mete_var(columns, var, filename)
      character(len=*), intent(in) :: columns(6), filename
      type(mete_var_type), intent(out) :: var
      integer :: stat

      var%name = columns(1)
      read (columns(2), *, iostat=stat) var%ndim
      if (stat /= 0) call fatal_error('invalid dimension for meteorology variable "'//trim(var%name)//'"')
      select case (trim(columns(3)))
      case ('standard')
         var%category = METE_STANDARD
      case ('diagnostic')
         var%category = METE_DIAGNOSTIC
      case default
         call fatal_error('unknown category "'//trim(columns(3))//'" in "'//trim(filename)//'"')
      end select
      call parse_logical(columns(4), var%output, var%name)
      var%unit = columns(5)
      var%description = columns(6)
   end subroutine parse_mete_var

   subroutine parse_logical(text, value, name)
      character(len=*), intent(in) :: text, name
      logical, intent(out) :: value

      select case (trim(text))
      case ('true')
         value = .true.
      case ('false')
         value = .false.
      case default
         call fatal_error('output flag for meteorology variable "'//trim(name)//'" must be true or false')
      end select
   end subroutine parse_logical

   subroutine parse_inputs(text, inputs, filename)
      character(len=*), intent(in) :: text, filename
      type(mete_input_type), allocatable, intent(out) :: inputs(:)
      character(len=128) :: item
      integer :: i, start, count, separator

      count = 1
      do i = 1, len_trim(text)
         if (text(i:i) == ';') count = count + 1
      end do
      allocate (inputs(count))
      start = 1
      do i = 1, count
         separator = index(text(start:), ';')
         if (separator == 0) then
            item = trim(adjustl(text(start:)))
         else
            item = trim(adjustl(text(start:start + separator - 2)))
         end if
         if (index(item, 'raw:') == 1) then
            inputs(i)%source = METE_INPUT_RAW
            inputs(i)%name = item(5:)
         else if (index(item, 'standard:') == 1) then
            inputs(i)%source = METE_INPUT_STANDARD
            inputs(i)%name = item(10:)
         else
            call fatal_error('invalid mapping input "'//trim(item)//'" in "'//trim(filename)//'"')
         end if
         if (len_trim(inputs(i)%name) == 0) call fatal_error('empty mapping input in "'//trim(filename)//'"')
         if (separator > 0) start = start + separator
      end do
   end subroutine parse_inputs

   subroutine validate_mete_table(table, filename)
      type(mete_table_type), intent(inout) :: table
      character(len=*), intent(in) :: filename
      integer :: i, j

      do i = 1, table%n_2d
         do j = i + 1, table%n_2d
            if (trim(table%var2ds(i)%name) == trim(table%var2ds(j)%name)) &
               call fatal_error('duplicate meteorology variable "'//trim(table%var2ds(i)%name)//'"')
         end do
         if (table%var2ds(i)%category == METE_STANDARD) table%n_standard_2d = table%n_standard_2d + 1
         if (table%var2ds(i)%category == METE_DIAGNOSTIC) table%n_diagnostic_2d = table%n_diagnostic_2d + 1
      end do
      do i = 1, table%n_3d
         do j = i + 1, table%n_3d
            if (trim(table%var3ds(i)%name) == trim(table%var3ds(j)%name)) &
               call fatal_error('duplicate meteorology variable "'//trim(table%var3ds(i)%name)//'"')
         end do
         if (table%var3ds(i)%category == METE_STANDARD) table%n_standard_3d = table%n_standard_3d + 1
         if (table%var3ds(i)%category == METE_DIAGNOSTIC) table%n_diagnostic_3d = table%n_diagnostic_3d + 1
      end do
      do i = 1, table%n_2d
         do j = 1, table%n_3d
            if (trim(table%var2ds(i)%name) == trim(table%var3ds(j)%name)) &
               call fatal_error('duplicate meteorology variable "'//trim(table%var2ds(i)%name)//'" in "'// trim(filename)//'"')
         end do
      end do
   end subroutine validate_mete_table

   subroutine validate_mapping_rows(mapping, filename)
      type(mete_mapping_table_type), intent(in) :: mapping
      character(len=*), intent(in) :: filename
      integer :: i, j

      do i = 1, mapping%nvar
         if (mapping%vars(i)%ndim /= 2 .and. mapping%vars(i)%ndim /= 3) &
            call fatal_error('mapping dimension must be 2 or 3 for "'//trim(mapping%vars(i)%name)//'"')
         if (.not. supported_method(mapping%vars(i)%method)) &
            call fatal_error('unsupported mapping method "'//trim(mapping%vars(i)%method)//'" in "'// trim(filename)//'"')
         do j = i + 1, mapping%nvar
            if (trim(mapping%vars(i)%name) == trim(mapping%vars(j)%name)) &
               call fatal_error('duplicate mapping target "'//trim(mapping%vars(i)%name)//'"')
         end do
      end do
   end subroutine validate_mapping_rows

   logical function supported_method(method)
      character(len=*), intent(in) :: method

      select case (trim(method))
      case ('direct', 'wrf_u_staggered', 'wrf_v_staggered', 'wrf_w_staggered', &
            'wrf_total_pressure', 'wrf_air_temperature', 'ideal_gas_density', &
            'wrf_virtual_theta', 'wrf_layer_thickness', 'wrf_layer_top_height')
         supported_method = .true.
      case default
         supported_method = .false.
      end select
   end function supported_method

   logical function skip_csv_line(line)
      character(len=*), intent(in) :: line
      character(len=len(line)) :: adjusted

      adjusted = adjustl(line)
      skip_csv_line = len_trim(adjusted) == 0 .or. adjusted(1:1) == '!'
   end function skip_csv_line

   subroutine split_csv(line, columns, filename)
      character(len=*), intent(in) :: line, filename
      character(len=*), intent(out) :: columns(:)
      integer :: i, start, separator

      columns = ''
      start = 1
      do i = 1, size(columns) - 1
         separator = index(line(start:), ',')
         if (separator == 0) call fatal_error('too few columns in CSV file "'//trim(filename)//'"')
         columns(i) = trim(adjustl(line(start:start + separator - 2)))
         start = start + separator
      end do
      if (index(line(start:), ',') /= 0) call fatal_error('too many columns in CSV file "'//trim(filename)//'"')
      columns(size(columns)) = trim(adjustl(line(start:)))
      if (any(len_trim(columns) == 0)) call fatal_error('empty column in CSV file "'//trim(filename)//'"')
   end subroutine split_csv

end module mod_mete_csv
