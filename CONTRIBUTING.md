# FlexCTM 开发与 Fortran 编码规范

本文适用于 `FlexCTM` 组织下的 FlexCTM 主程序及其 Fortran 库，参考了
[Fortran-lang Best Practices](https://fortran-lang.org/learn/best_practices/)。文中的“必须”仅用于会影响正确性、
接口兼容性或协作一致性的要求；“建议”表示通常更好的做法，但可以根据数值算法、性能和既有接口作出有理由的选择。

## 1. 目录原则

### 1.1 库仓库

除 FlexCTM 主程序外，仓库默认是库，采用以下结构：

```text
library/
├── src/                  # 库实现；不得包含 program
├── example/              # 可运行案例；每个文件一个独立 program
├── test/                 # 自动化测试
├── pages/                # 可选：FORD 页面源文件
├── media/                # 可选：文档图片
├── utils/                # 仅放构建或开发辅助工具
├── CMakeLists.txt
├── Makefile
├── fpm.toml
├── README.md
└── CONTRIBUTING.md       # 可引用本规范
```

不需要的目录不得保留为空。构建产物只能进入 `build/`，生成文档只能进入 `_site/`，不得提交 `.o`、`.mod`、静态库或可执行文件。

正确：

```text
example/uniform_pulse.f90
example/nonuniform_pulse.f90
```

错误：

```text
app/main.f90              # 库没有真正的应用入口
example/main.f90          # 名称没有表达场景
src/demo.f90              # program 混入库源码
```

### 1.2 FlexCTM 主程序

FlexCTM 是应用程序，可以保留 `app/`：

```text
FlexCTM/
├── app/                  # 唯一的程序入口
├── src/                  # 领域模块和驱动层
├── test/                 # 单元及集成测试
├── meta/                 # 受版本控制的小型元数据
├── example/              # 可选：独立、最小运行配置
└── pages/                # 用户和开发文档
```

输入数据、运行输出、缓存和大型 NetCDF 文件不得放入源码目录。

### 1.3 文件命名

库仓库应提供与仓库同名的公开 facade 模块。内部模块名称应表达职责；新模块可以使用 `<库名>_<职责>`，但不应仅为统一前缀而重命名稳定的既有模块。

正确：

```fortran
module diffusion
module diffusion_vertical
module diffusion_horizontal
```

不推荐用于新模块：

```fortran
module mod_vdiff
module module_tool
```

一个源文件通常只定义一个主要 module，文件名与 module 名对应并使用小写 snake_case。紧密关联的小型辅助程序单元可以同文件放置；仅需要预处理的文件使用 `.F90`，其他文件使用 `.f90`。

## 2. Fortran 编码规范

### 2.1 使用现代自由格式和显式语义

每个 module、program 和外部 procedure 都必须声明 `implicit none`。fpm 中同时保持：

```toml
[fortran]
implicit-typing = false
implicit-external = false
source-form = "free"
```

正确：

```fortran
module transport
   implicit none
   private
end module transport
```

错误：

```fortran
module transport
   real :: concetration  ! 拼写错误会静默成为新变量
end module transport
```

### 2.2 控制公共符号

对外提供 API 的模块应默认 `private`，再显式列出公共符号，避免实现细节意外成为 API。内部模块也建议采用相同方式；如果省略，必须明确该模块不属于稳定接口。

module 变量具有隐含的 `save` 语义，应优先用于命名常量。必须保存可变模块状态时，应限制可见性并通过过程维护其不变量；只允许外部读取的状态可以声明为 `protected`。

正确：

```fortran
module projection
   implicit none
   private
   public :: projection_type, create_projection
end module projection
```

错误：

```fortran
module projection
   implicit none
   ! 所有辅助过程和常量意外公开
end module projection
```

### 2.3 优先使用 `only`

`use` 语句建议使用 `only`，使依赖关系清楚并避免名称冲突。对于 `mpi`、`netcdf` 等使用大量符号的外部模块，或者明确用于重新导出的 facade，可以根据可读性省略 `only`。重命名只用于消除冲突或澄清语义。

正确：

```fortran
use, intrinsic :: iso_fortran_env, only: error_unit, real64
use diffusion, only: vdiff_by_k_theory
```

不推荐用于内部依赖：

```fortran
use diffusion
```

MPI 新代码优先使用 `mpi_f08`；迁移旧 `use mpi` 前必须验证派生类型句柄和编译器兼容性。

### 2.4 命名与领域符号

新代码中的 module、procedure、变量和命名参数使用小写 snake_case；派生类型通常以 `_type` 结尾。名称应在其作用域内清楚，不要求把公式、文献或领域中公认的符号展开成长名称。

正确：

```fortran
type :: grid_meta_type
logical :: is_global
integer :: n
real(fp) :: c(n), dc(n), u(n - 1)
real(fp) :: dx, c6
call calculate_kz_by_ysu(...)
```

不推荐：

```fortran
real(fp) :: var1
real(fp) :: temp2
call do_work(...)
```

`n`、`i`、`u`、`c`、`dc`、`dx`、`ds`、`c6`、`fp`、`kz` 等在公式、文献或领域中含义明确的短名可以使用。临时变量只需在局部上下文中清楚；公共类型和过程名称应更具描述性。新 API 的动词应保持同一仓库内一致，但不为追求统一而立即破坏已有 API。

### 2.5 声明、空格和行长

声明使用 `::`，同类声明保持一致的属性顺序。缩进统一使用 3 个空格，不混用制表符。代码行建议不超过 120 列；较长表达式在运算符或实参边界换行。

正确：

```fortran
real(fp), allocatable, intent(out) :: concentration(:, :)

call calculate_diffusivity( &
   pbl_height=pbl_height, friction_velocity=friction_velocity, &
   diffusivity=diffusivity, stat=stat)
```

不推荐：

```fortran
real(fp), intent(out), allocatable::concentration(:,:)
call calculate_diffusivity(pbl_height,friction_velocity,inverse_obukhov_length,height,layer_thickness,u,v,theta,diffusivity,status)
```

当位置实参容易混淆，特别是多个相同类型、相同量纲的标量连续出现时，建议使用关键字实参。短小且顺序符合领域惯例的接口可以使用位置实参。

### 2.6 kind 和字面量

浮点 kind 应来自 `iso_fortran_env` 或库统一公开的 `fp`。精度敏感表达式中的实数字面量应带 kind 后缀，避免先按默认精度求值。

正确：

```fortran
use, intrinsic :: iso_fortran_env, only: real64
integer, parameter :: fp = real64
real(fp), parameter :: half = 0.5_fp
```

不推荐：

```fortran
real(fp) :: half = 0.5
```

同一个公共 API 中必须使用一致的浮点 kind。跨库传递实数时，应明确各库的 kind 是否一致，不能依赖编译器默认精度。

整数相除执行整数运算，并按从左到右的顺序计算同优先级运算。需要实数结果时，应在除法前显式转换：

```fortran
ratio = real(count, fp)/real(total, fp)
```

不要写成：

```fortran
ratio = count/total ! Integer division occurs before assignment. / 赋值前已经执行整数除法。
```

### 2.7 数值比较和容差

对迭代、解析计算或观测得到的浮点结果，应使用与问题尺度相关的容差。若某个值是调用方直接设置的状态标记，或者代码需要区分速度的精确符号，可以直接比较。

正确：

```fortran
scale = max(1.0_fp, abs(reference))
if (abs(value - reference) <= 100.0_fp * epsilon(value) * scale) then
   ! values agree
end if
```

不推荐用于计算结果：

```fortran
if (computed_value == reference) return
```

### 2.8 过程属性和副作用

适合且不会限制实现的无副作用过程建议声明为 `pure`；逐元素独立的过程可以声明为 `elemental`。可复用数值内核不应打印调试日志或读取无关的全局配置。

正确：

```fortran
pure elemental real(fp) function square(x) result(y)
   real(fp), intent(in) :: x
   y = x * x
end function square
```

不推荐在可复用数值过程中加入输出副作用：

```fortran
real function square(x)
   print *, "calculate square"
   square = x * x
end function square
```

### 2.9 内存所有权

拥有动态内存时优先使用 `allocatable`；别名、视图、链式结构或互操作场景可以使用 `pointer`。返回内部指针的 API 必须说明其生命周期以及哪些操作会使指针失效。

读取 allocatable 变量前应保证其已分配。`allocatable, intent(out)` 实参进入过程时会自动释放原有分配；接口使用这一语义时应在文档中说明。转移大型分配所有权时可以使用 `move_alloc`。

正确：

```fortran
real(fp), allocatable :: values(:)
allocate(values(n), stat=stat, errmsg=message)
```

需谨慎：

```fortran
class(*), pointer :: value
value => map%get_value_ptr("species") ! map 修改或 clear 后失效
```

### 2.10 I/O 单元

打开普通文件时应使用 `newunit`，避免硬编码单元号。可能正常失败的 I/O 应处理 `iostat`，需要向上返回原因时同时使用 `iomsg`；所有成功打开的文件都应在相应路径关闭。

正确：

```fortran
integer :: unit, io_stat
character(256) :: io_message

open(newunit=unit, file=filename, status="old", action="read", &
   iostat=io_stat, iomsg=io_message)
if (io_stat /= 0) then
   stat = error_io
   message = trim(io_message)
   return
end if
close(unit)
```

不推荐：

```fortran
open(unit=10, file=filename)
read(10, *) value
```

### 2.11 注释和文档

注释用于解释意图、单位、边界条件和算法来源，不复述代码。公开 API 使用 FORD 可识别的 `!!` 文档，并说明影响正确使用的参数、单位和数组布局。局部变量在名称不足以说明含义时添加简短注释；循环下标等上下文明确的变量不必机械注释。

正确：

```fortran
subroutine mix_column(dt, dz, diffusivity, concentration)
   !! Apply zero-flux vertical mixing.
   real(fp), intent(in) :: dt                 !! Time step [s]
   real(fp), intent(in) :: dz(:)              !! Layer thickness [m]
   real(fp), intent(inout) :: concentration(:) !! Cell mean [kg m-3]
```

不推荐复述代码本身：

```fortran
i = i + 1 ! Add one to i
real :: pbl ! pbl
```

本组织新增或修改的接口注释采用英文在前、中文在后的顺序。两种语言表达相同契约；公式符号、单位和专业术语保持一致。无需为了双语形式重复显而易见的逐行注释。

```fortran
real(fp), intent(in) :: dt !! Time step [s] / 时间步长 [s]
```

## 3. API 设计规范

### 3.1 facade 与实现分离

每个库应通过与仓库同名的 facade module 暴露稳定 API。内部模块可以自由演化，下游不应依赖；确有高级用途需要暴露内部能力时，应明确其稳定性和兼容性承诺。

正确：

```fortran
use advection, only: adv1d_by_ppm, fp
```

不推荐：

```fortran
use mod_ppm, only: adv1d_by_ppm
```

### 3.2 实参顺序

公开过程通常按以下顺序组织实参：必需输入、被修改状态、输出、可选参数、错误状态。泛型区分或领域惯例需要其他顺序时可以调整，但同一组重载必须一致。多个同类型实参容易混淆时，调用端建议使用关键字实参。

数据实参应显式声明 `intent(in)`、`intent(out)` 或 `intent(inout)`。可选实参必须声明 `optional`，并在引用前使用 `present` 判断。公开数组实参优先使用 assumed-shape，由显式接口传递形状信息。

推荐使用关键字实参澄清含义：

```fortran
call vertical_mix( &
   dt=dt, layer_thickness=dz, diffusivity=kz, density=rho, &
   concentration=concentration, stat=stat)
```

位置实参容易混淆时不推荐：

```fortran
call vertical_mix(dt, dz, kz, rho, concentration, stat)
```

### 3.3 数组契约

数组 API 必须说明影响正确调用的维度顺序、有效区间、halo、边界语义、单位、别名限制、连续性要求和尺寸关系。高层入口通常负责检查外部输入；频繁调用的数值内核可以公开声明前置条件，由调用方统一保证。

Fortran 多维数组按列主序存储，最左侧下标连续。性能敏感循环通常让最左侧下标位于最内层；只有过程确实要求连续存储时才给实参加 `contiguous`，并把这一要求写入接口契约。

正确：

```fortran
if (size(dz) /= size(concentration)) then
   stat = error_shape
   message = "dz and concentration must have equal sizes"
   return
end if
```

未满足已声明的尺寸契约时属于错误：

```fortran
do k = 1, size(dz)
   concentration(k) = concentration(k) + tendency(k) ! tendency 可能更短
end do
```

### 3.4 避免用可选参数表达互斥模式

两个互斥的可选参数容易产生“两者都给”或“两者都不给”的非法状态。新接口优先拆分 generic procedure，或使用明确的配置类型；简单、稳定且能清楚校验的既有接口不要求立即迁移。

推荐：

```fortran
interface advect_1d
   module procedure advect_uniform_grid
   module procedure advect_variable_grid
end interface advect_1d
```

不推荐：

```fortran
subroutine advect_1d(..., dx, ds)
   real(fp), optional, intent(in) :: dx
   real(fp), optional, intent(in) :: ds(:)
```

### 3.5 相关配置可以使用派生类型

稳定、反复共同传递且数量较多的一组参数，可以封装为派生类型。短小的数值过程不应为了形式统一而额外引入配置类型。

适合参数稳定且反复共同传递的情况：

```fortran
type :: pbl_config_type
   real(fp) :: roughness_length
   real(fp) :: pbl_height
contains
   procedure :: validate
end type pbl_config_type
```

出现以下长实参列表时应评估是否需要配置类型：

```fortran
call calculate_pbl(t0, t1, p0, p1, dz, wind, z0, pbl, ri, ustar, rmol, wstar)
```

### 3.6 热路径和诊断路径分离

数值内核负责计算，日志、布局打印和文件 I/O 放在驱动层。只有测量确认分配成本显著时，才引入调用方工作数组或 workspace；很小的自动数组不需要提前优化。

确认存在性能收益后，可以复用工作空间：

```fortran
call workspace%ensure_size(nz, stat)
call solve_vertical_diffusion(state, workspace, stat)
```

不推荐在热点中混合重复分配和诊断输出：

```fortran
subroutine solve_vertical_diffusion(...)
   real(fp), allocatable :: matrix(:, :)
   allocate(matrix(nz, nz)) ! 每个网格柱、每个时间步重复分配
   print *, "solving"
```

### 3.7 数值接口的有效域与性质

数值接口必须写明影响正确性的有效域，例如 `dt > 0`、`dz > 0`、密度为正、CFL 上限和边界语义。测试应覆盖接口实际承诺的性质，例如守恒、精度趋势、非负性或单调性；不要测试算法并未承诺的性质。

正确：

```fortran
mass_before = sum(rho * concentration * dz)
call vertical_mix(...)
mass_after = sum(rho * concentration * dz)
call check(error, mass_after, mass_before, thr=1.0e-12_fp)
```

没有验证任何数值承诺：

```fortran
call vertical_mix(...)
print *, concentration
```

### 3.8 API 兼容性

公共 API 的名称、实参类型、kind、rank、顺序和语义都属于兼容性的一部分。已发布接口的破坏性修改必须说明迁移方法；添加可选实参时通常放在末尾，generic 重载必须能够由 Fortran 的类型、kind 或 rank 明确区分。

尚未发布的仓库可以在首次稳定发布前直接整理接口。内部模块不承诺兼容性，但修改后仍需通过 facade 的测试。

## 4. 错误处理规范

### 4.1 库不得决定进程退出

可恢复错误由库返回，应用层决定重试、降级或退出。`stop`、`error stop` 和 `MPI_Abort` 只允许出现在 `app/`、案例、测试或确认不可恢复的应用边界，不得出现在可复用库的普通输入校验中。

正确：

```fortran
integer, parameter :: success = 0, error_invalid_argument = 1

subroutine reserve(map, capacity, stat, message)
   integer, intent(out) :: stat
   character(:), allocatable, intent(out) :: message

   if (capacity < 0) then
      stat = error_invalid_argument
      message = "capacity must be non-negative"
      return
   end if
   stat = success
   message = ""
end subroutine reserve
```

错误：库过程直接终止调用方进程。

```fortran
if (capacity < 0) then
   write(*, *) "bad capacity"
   stop 1
end if
```

### 4.2 错误信息保持简单

可能因外部输入、文件、资源或运行环境失败的过程，必须让调用方能够判断失败并获得足够上下文。Fortran 库通常使用整数状态码和错误信息；同一仓库应采用一致约定。满足已记录前置条件后不会失败的数值内核，不必统一增加 `stat/message`。

正确：

```fortran
call read_metadata(filename, metadata, stat, message)
if (stat /= success) then
   write(error_unit, "(a)") "read metadata: " // message
   error stop 1
end if
```

错误：失败被隐藏在函数内部，调用方无法处理。

```fortran
metadata = read_metadata(filename) ! 失败时内部 stop，调用方无法处理
```

### 4.3 明确失败后的输出状态

提供错误返回的过程，必须定义失败路径上的 `stat`、`message` 和调用方可能读取的输出。是否清零大型输出数组应由接口契约决定；不要求为调用方不得读取的失败结果付出额外热路径成本。需要原子更新时，先写临时对象，成功后再 `move_alloc` 或赋值。

正确：

```fortran
stat = success
message = ""
result = 0.0_fp
if (.not. valid) then
   stat = error_invalid_argument
   message = "latitude is outside [-90, 90]"
   return
end if
```

错误：

```fortran
if (.not. valid) return ! result 和 stat 未定义
```

### 4.4 MPI 错误必须协同处理

MPI 库不得让单个 rank 在其他 rank 仍处于 collective 时直接 `stop`。先形成局部状态，再通过 communicator 汇总；由所有 rank 走同一清理路径。只有应用层确认无法恢复时才调用 `MPI_Abort`。

正确：

```fortran
call MPI_Allreduce(local_stat, global_stat, 1, MPI_INTEGER, MPI_MAX, comm, ierr)
if (global_stat /= success) then
   call process%clear()
   return
end if
```

错误：

```fortran
if (nx < nhalo) stop 1 ! 其他 rank 可能永久等待
```

### 4.5 日志只在边界层输出

库返回错误信息，由应用决定是否输出。错误输出使用 `error_unit`；MPI 程序通常仅由 root 输出一次。需要诊断日志时使用统一入口或明确的 verbosity，不在数值过程里散落 `print *`。

正确：

```fortran
use, intrinsic :: iso_fortran_env, only: error_unit
if (process%is_root()) write(error_unit, "(a)") trim(message)
```

不推荐散落调试输出：

```fortran
if (debug_enabled) print *, "open file"
```

## 5. 测试规范

测试按行为组织，每个测试应有清楚的名称和失败原因。根据接口承诺选择正常路径、边界值、守恒、方向、精度趋势和错误处理测试；只有接口负责检查非法输入时，才测试非法输入。案例用于说明调用方式，不能代替自动化测试。

正确：

```fortran
tests = [ &
   new_unittest("vertical diffusion conserves mass", test_mass_conservation), &
   new_unittest("negative layer thickness is rejected", test_negative_dz) &
]
```

名称过于笼统：

```fortran
tests = [new_unittest("check", test_everything)]
```

浮点测试使用与精度和问题尺度匹配的容差，不依赖格式化后的文本比较。数值算法应测试它明确承诺的性质；精度测试优先使用解析解、可信参考值或网格加密趋势。MPI 代码至少覆盖一个真实的多进程场景并设置超时；进程数组合根据通信拓扑和 CI 成本选择。修复 bug 时应同时增加能够复现问题的回归测试。
