module mod_chem_type
   !! FlexCTM 化学变量的身份、输送及过程调度定义。
   use mod_const, only: fp
   implicit none
   private

   integer, parameter, public :: CHEM_REACTIVE = 1
   integer, parameter, public :: CHEM_PASSIVE = 2
   integer, parameter, public :: CHEM_DIAGNOSTIC = 3

   type, public :: chem_species_type
      character(len=32) :: name = ''          !! FlexCTM 标准变量名。
      character(len=16) :: phase = ''         !! gas、aerosol 或 diagnostic。
      integer :: role = 0                     !! reactive、passive 或 diagnostic。
      logical :: transported = .false.        !! 是否分配并推进输送状态。
      logical :: advected = .false.           !! 是否参加平流。
      logical :: diffused = .false.           !! 是否参加扩散。
      logical :: read_initial = .false.       !! 是否读取初始场。
      logical :: read_boundary = .false.      !! 是否读取边界场。
      logical :: read_emission = .false.      !! 是否读取排放场。
      logical :: use_chemistry = .false.      !! 是否交给化学求解器。
      logical :: dry_deposition = .false.     !! 是否参加干沉降。
      logical :: wet_deposition = .false.     !! 是否参加湿沉降。
      logical :: write_output = .false.       !! 是否写入模式输出。
      character(len=32) :: unit = ''          !! FlexCTM 内部单位。
      real(fp) :: molar_mass = 0._fp          !! 摩尔质量 [g mol-1]。
      character(len=128) :: description = ''  !! 变量含义。
   end type chem_species_type

   type, public :: chem_table_type
      integer :: nvar = 0        !! 化学变量总数。
      integer :: ngas = 0        !! 气相变量数。
      integer :: naerosol = 0    !! 气溶胶变量数。
      integer :: ntransported = 0 !! 参加输送的变量数。
      integer :: nreactive = 0   !! 参加化学反应的变量数。
      integer :: nemission = 0   !! 读取排放的变量数。
      integer :: noutput = 0     !! 输出变量数。
      type(chem_species_type), allocatable :: vars(:)
      integer, allocatable :: transported_indices(:)
      integer, allocatable :: reactive_indices(:)
      integer, allocatable :: emission_indices(:)
      integer, allocatable :: output_indices(:)
   contains
      procedure :: idx => chem_table_idx
      procedure :: contain => chem_table_contain
   end type chem_table_type

contains

   logical function chem_table_contain(this, name) result(found)
      class(chem_table_type), intent(in) :: this
      character(len=*), intent(in) :: name
      found = this%idx(name) > 0
   end function chem_table_contain

   integer function chem_table_idx(this, name) result(index)
      class(chem_table_type), intent(in) :: this
      character(len=*), intent(in) :: name
      integer :: i
      index = 0
      do i = 1, this%nvar
         if (trim(this%vars(i)%name) == trim(name)) then
            index = i
            return
         end if
      end do
   end function chem_table_idx

end module mod_chem_type
