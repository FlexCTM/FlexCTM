---
title: Fortran 编码习惯
---

# Fortran 编码习惯

这些约定用于保持主仓接口简单、类型安全并且易于并行调试。

## 1. 模块结构

```fortran
module mod_example
   use mod_const, only: fp
   implicit none
   private

   public :: update_example

contains

   subroutine update_example(field, dt)
      real(fp), intent(inout) :: field(:, :, :)
      real(fp), intent(in) :: dt
   end subroutine update_example
end module mod_example
```

- 每个 module 使用 `implicit none`；
- 默认 `private`，再显式列出 `public`；
- `use` 优先带 `only`，避免隐式名称依赖；
- 公开过程的虚参数都写 `intent`；
- 变量声明放在可执行语句之前。

## 2. 命名

| 对象 | 约定 | 示例 |
|---|---|---|
| 模块、过程、变量 | 小写 `snake_case` | `read_mete_field` |
| 派生类型 | `_type` 后缀 | `chem_table_type` |
| 布尔值 | 使用表达状态的名称 | `is_global`, `restart` |
| 数量 | `n` 或 `n_` 前缀 | `nlev`, `n_standard_3d` |
| 下标范围 | 与并行网格术语一致 | `ibs`, `ibe`, `jbs`, `jbe` |

同一概念在代码、配置、元数据和文档中使用同一名称。例如二维气象数组始终写为 `mete2d(x, y, meteorological_variable)`。

## 3. 数值精度

- 浮点变量使用所属包公开的 `fp`，不使用 `real(4)` 或 `real(8)`；
- 精度相关字面量写为 `0.0_fp`、`0.5_fp`；
- 比较浮点数时根据量纲和计算尺度定义容差；
- 改动 kind、I/O 类型或数值包边界时，同时验证 real64 和 real32。

## 4. 数组与并行数据

- 在公开接口注释中按顺序写明每一维的含义；
- 区分包含 halo 的分配区 `1:nx, 1:ny` 和有效区 `ibs:ibe, jbs:jbe`；
- 向 MPI 或 NetCDF 传递切片前确认连续性和全局/局地下标转换；
- 不在底层 kernel 中隐式分配与 domain 尺寸相同的大型工作数组；
- 指针别名不拥有内存，释放 target 前先 `nullify`。

## 5. 控制流与错误

- 优先使用短小、单一职责的过程；
- 对字符串枚举使用 `select case`，并处理 `case default`；
- I/O 调用检查 `iostat` 或库状态码，错误信息包含文件和操作；
- 可复用数值过程优先用 `stat` 和 `errmsg` 返回错误；
- 只在应用层确定无法继续时调用 `fatal_error`。

## 6. 格式、注释和 API 文档

- 使用自由格式 Fortran，缩进 3 个空格；
- 每行建议不超过 120 个字符；
- 注释说明单位、数组布局、边界条件和设计原因，不重述代码表面行为；
- 公开 module、类型和过程使用 `!!` FORD 注释；
- 接口行为变更时，在同一修改中更新测试和对应文档。
