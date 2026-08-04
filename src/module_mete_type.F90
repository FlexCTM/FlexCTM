module mod_mete_type
   !! FlexCTM 标准气象变量表和数据集接口映射类型。
   implicit none
   private

   integer, parameter, public :: METE_STANDARD = 1
   integer, parameter, public :: METE_DIAGNOSTIC = 2
   integer, parameter, public :: METE_INPUT_RAW = 1
   integer, parameter, public :: METE_INPUT_STANDARD = 2

   type, public :: mete_var_type
      character(len=32) :: name = ''         !! FlexCTM 标准变量名。
      integer :: ndim = 0                    !! 空间维数，只允许 2 或 3。
      integer :: category = 0                !! METE_STANDARD 或 METE_DIAGNOSTIC。
      logical :: output = .false.            !! 是否写入气象诊断输出。
      character(len=32) :: unit = ''         !! FlexCTM 标准单位。
      character(len=128) :: description = '' !! 变量含义说明。
   end type mete_var_type

   type, public :: mete_table_type
      integer :: n_2d = 0            !! 二维变量总数。
      integer :: n_3d = 0            !! 三维变量总数。
      integer :: n_standard_2d = 0   !! 二维标准输入变量数。
      integer :: n_standard_3d = 0   !! 三维标准输入变量数。
      integer :: n_diagnostic_2d = 0 !! 二维公共诊断变量数。
      integer :: n_diagnostic_3d = 0 !! 三维公共诊断变量数。
      type(mete_var_type), allocatable :: var2ds(:) !! 二维变量定义。
      type(mete_var_type), allocatable :: var3ds(:) !! 三维变量定义。
   contains
      procedure :: contain => mete_table_contain
      procedure :: idx => mete_table_idx
   end type mete_table_type

   type, public :: mete_input_type
      integer :: source = 0           !! METE_INPUT_RAW 或 METE_INPUT_STANDARD。
      character(len=32) :: name = ''  !! 原始数据名或标准变量名。
   end type mete_input_type

   type, public :: mete_mapping_type
      character(len=32) :: name = ''         !! 目标标准变量名。
      integer :: ndim = 0                    !! 目标变量空间维数。
      type(mete_input_type), allocatable :: inputs(:) !! 读取或诊断依赖项。
      character(len=32) :: method = ''       !! 数据集接口处理方法。
      character(len=32) :: source_unit = ''  !! 原始输入单位或 mixed。
      character(len=32) :: target_unit = ''  !! 生成后的标准单位。
      character(len=128) :: description = '' !! 映射说明。
   end type mete_mapping_type

   type, public :: mete_mapping_table_type
      integer :: nvar = 0 !! 接口映射条目数。
      type(mete_mapping_type), allocatable :: vars(:) !! 接口映射定义。
   contains
      procedure :: contain => mete_mapping_contain
      procedure :: idx => mete_mapping_idx
   end type mete_mapping_table_type

contains

   logical function mete_table_contain(this, name) result(found)
      class(mete_table_type), intent(in) :: this
      character(len=*), intent(in) :: name

      found = this%idx(name) > 0
   end function mete_table_contain

   integer function mete_table_idx(this, name, ndim) result(index)
      class(mete_table_type), intent(in) :: this
      character(len=*), intent(in) :: name
      integer, optional, intent(out) :: ndim
      integer :: i

      index = 0
      if (present(ndim)) ndim = 0
      do i = 1, this%n_2d
         if (trim(this%var2ds(i)%name) == trim(name)) then
            index = i
            if (present(ndim)) ndim = 2
            return
         end if
      end do
      do i = 1, this%n_3d
         if (trim(this%var3ds(i)%name) == trim(name)) then
            index = i
            if (present(ndim)) ndim = 3
            return
         end if
      end do
   end function mete_table_idx

   logical function mete_mapping_contain(this, name) result(found)
      class(mete_mapping_table_type), intent(in) :: this
      character(len=*), intent(in) :: name

      found = this%idx(name) > 0
   end function mete_mapping_contain

   integer function mete_mapping_idx(this, name) result(index)
      class(mete_mapping_table_type), intent(in) :: this
      character(len=*), intent(in) :: name
      integer :: i

      index = 0
      do i = 1, this%nvar
         if (trim(this%vars(i)%name) == trim(name)) then
            index = i
            return
         end if
      end do
   end function mete_mapping_idx

end module mod_mete_type
