module mod_tool
    !! 通用辅助过程
   use mod_const, only: fp, P00, vk, R_cp, g, eps
   use mod_error, only: fatal_error

   implicit none
   private

   public :: get_filename, does_file_exist

contains

   recursive function replace_string(str, pattern, replace) result(res)
        !! 替换字符串中所有匹配的子串。
      implicit none
      character(*), intent(in) :: str
      character(*), intent(in) :: pattern
      character(*), intent(in) :: replace
      character(:), allocatable :: res

      integer :: i

      i = index(str, pattern)
      if (i == 0) then
         allocate (character(len_trim(str)) :: res)
         res = str
         return
      end if
      allocate (character((len_trim(str) - len(pattern) + len_trim(AdjustL(replace)))) :: res)

      res = str(1:i - 1)//trim(AdjustL(replace))//str(i + len(pattern):len_trim(str))

      res = replace_string(res, pattern, replace)

   end function replace_string

   function get_filename(str, sector, domain) result(filename)
        !! 根据占位字段生成文件名。
      implicit none
      character(*), intent(in) :: str
      character(*), optional, intent(in) :: sector
      character(*), optional, intent(in) :: domain

      character(:), allocatable :: filename

      allocate (character(len_trim(str)) :: filename)
      filename = str
      if (present(sector)) filename = replace_string(filename, '[SECTOR]', sector)
      if (present(domain)) filename = replace_string(filename, '[DOMAIN]', domain)

   end function get_filename

   logical function does_file_exist(fileName, must) result(lstat)
        !! 检查文件是否存在。
      implicit none
      character(len=*), intent(in) :: filename
      logical, optional, intent(in) :: must    !! 是否必须存在
      logical :: required

      inquire (file=fileName, exist=lstat)

      required = .false.
      if (present(must)) required = must
      if (required .and. .not. lstat) &
         call fatal_error('required file does not exist: "'//trim(filename)//'"')
   end function does_file_exist

end module mod_tool
