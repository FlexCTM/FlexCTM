---
title: 数据结构
---

# 数据结构

FlexCTM 以 `block_type` 为时间推进的主状态容器，以元数据表定义变量身份和过程属性。本章中的维度名称与代码一致。

## 1. 并行网格对象

`parallel` 软件包提供三类网格对象：

| 类型 | 含义 |
|---|---|
| `process_type` | MPI communicator、当前 rank、所有 domain 和切片的集合 |
| `domain_type` | 一个全局 domain 的尺寸、拓扑和垂直层数 |
| `tile_type` | 当前 rank 在一个 domain 中的有效区、halo 和邻居 |
| `bridge_type` | 父子 domain 的网格对应和边界交换尺寸 |

`block_type%nx` 和 `%ny` 包含水平 halo，`%nz` 是垂直质量层数，不含垂直 halo。有效计算区为 `ibs:ibe, jbs:jbe`。

## 2. `mesh_type`

`block_type%mesh` 保存当前局地切片的水平网格：

| 成员 | shape | 含义 |
|---|---|---|
| `mlon`, `mlat` | `(nx, ny)` | 质量网格中心经纬度 |
| `clon`, `clat` | `(nx+1, ny+1)` | 网格角点经纬度 |
| `xlen`, `ylen` | `(nx, ny)` | 网格 X/Y 方向长度 |
| `area` | `(nx, ny)` | 水平面积 |
| `dx_mean` | `(ny)` | 每个 Y 位置的平均 X 间距 |
| `dy_mean` | `(nx)` | 每个 X 位置的平均 Y 间距 |

`xorg`、`yorg` 是包含 halo 后的局地西南角；`delta` 的单位由投影决定，经纬度网格使用度，投影网格使用米。

## 3. 化学元数据

`chem_species_type` 描述一个化学或诊断变量：

- `name`、`phase`、`role` 定义变量身份；
- `transported`、`advected`、`diffused` 控制输送过程；
- `read_initial`、`read_boundary`、`read_emission` 控制输入；
- `use_chemistry`、`dry_deposition`、`wet_deposition` 控制物理化学过程；
- `write_output`、`unit`、`molar_mass`、`description` 描述输出和物性。

`chem_table_type%vars(:)` 保留完整变量表，`transported_indices`、`reactive_indices`、`emission_indices` 和 `output_indices` 保存各过程的一基变量下标。`idx(name)` 和 `contain(name)` 用名称查询，算法不应假定 CSV 行号。

## 4. 气象元数据

`mete_var_type` 定义标准名称、`ndim`、`category`、`output`、单位和描述。`mete_table_type` 分别保存 `var2ds(:)` 和 `var3ds(:)`，并统计标准变量和公共诊断变量的数量。

`mete_mapping_type` 只用于数据集接口。它将一个标准变量关联到：

- `inputs(:)`：外部原始变量或已生成的标准变量；
- `method`：直接读取、去交错或诊断方法；
- `source_unit` 和 `target_unit`：转换前后单位。

## 5. `block_type`

### 主数组

| 成员 | 逻辑 shape | 含义 |
|---|---|---|
| `chem3d` | `(x, y, z, chemical_variable, time_window)` | 化学浓度和诊断输送量 |
| `emis3d` | `(x, y, z, chemical_variable)` | 当前排放场 |
| `mete3d` | `(x, y, z, meteorological_variable)` | 当前积分时刻的三维气象场 |
| `mete3d_1`, `mete3d_2` | 同 `mete3d` | 包围当前时刻的两个气象输入时次 |
| `mete2d` | `(x, y, meteorological_variable)` | 当前积分时刻的二维气象场 |
| `mete2d_1`, `mete2d_2` | 同 `mete2d` | 包围当前时刻的两个气象输入时次 |
| `rho_next` | `(x, y, z)` | 下一积分时刻的干空气密度 |
| `terrain` | `(x, y)` | 地形高度 |

`m3d_idx` 和 `m2d_idx` 把标准气象名称映射到最后一维的一基下标。

### 指针别名

常用变量直接指向 `mete3d` 或 `mete2d` 的某一个变量切片：

| 维度 | 别名 |
|---|---|
| 三维 | `u`, `v`, `w`, `dz`, `zt`, `dzdt`, `rho`, `volume`, `T`, `thetav`, `P`, `kx`, `ky`, `kz` |
| 二维 | `TSK`, `PSFC`, `PBL`, `Ri`, `RMOL`, `ustar`, `wstar` |
| 化学状态 | `rho_cctm` 指向 `chem3d(:, :, :, rho_index, twindow)` |

别名不拥有内存。`block_type%clear()` 先 `nullify` 全部别名，再释放可分配数组。

### 边界

`edge_type%bc(x, y, z, chemical_variable)` 保存一个方向的化学边界。`edges(4)` 对应当前 domain 的西、东、南、北外边界；`coarse_edges(4)` 保存从父 domain 接收的粗网格边界。

## 6. 生命周期和所有权

1. `app/main.f90` 为每个 domain 分配一个 `block_type`；
2. `block_type%init()` 复制元数据，根据 tile 尺寸分配数组，建立名称索引和指针别名；
3. I/O、诊断和 driver 在时间积分中原地更新状态；
4. `clear()` 释放状态，finalizer 保证离开作用域时执行同样的清理。

过程保存指向 `block_type` 内部数组的指针时，其生命期不得超过所属 `block_type`。
