---
title: 配置与输入数据
---

# 配置与输入数据

运行配置由 namelist、化学变量表和气象变量表共同组成。所有相对路径都相对于启动 `FlexCTM.exe` 时的当前工作目录。

## 1. namelist 结构

配置文件必须按以下顺序包含七个分组：

| 顺序 | 分组 | 作用 |
|---:|---|---|
| 1 | `&region` | domain 数量、尺寸和嵌套关系 |
| 2 | `&proj` | 投影、根网格原点和分辨率 |
| 3 | `&time` | 起始时间、积分时长和时间步 |
| 4 | `&physics` | halo 宽度和化学时间层 |
| 5 | `&chem` | 化学元数据、初边值和排放 |
| 6 | `&mete` | 气象标准表、数据集映射和时间间隔 |
| 7 | `&output` | 模式输出和静态网格输出 |

读取器按该顺序消费文件；不得交换分组顺序。

## 2. 网格与投影

### `&region`

| 字段 | 含义 | 约束 |
|---|---|---|
| `ndom` | domain 数 | 1–8 |
| `nlev` | 垂直质量层数 | 正整数；所有 domain 相同 |
| `we`, `sn` | 各 domain 的 X/Y 有效格点数 | 正整数，不含 halo |
| `parent_id` | 父 domain 的一基编号 | 根 domain 为 0；子 domain 引用更早定义的 domain |
| `i_parent_start`, `j_parent_start` | 子 domain 西南角在父网格中的一基下标 | 按 domain 给值 |
| `parent_grid_ratio` | 子/父水平分辨率比 | 正整数 |

子 domain 的 `delta` 和 `dt` 分别为父 domain 对应值除以 `parent_grid_ratio`。

### `&proj`

| 字段 | 含义 |
|---|---|
| `proj_id=0` | 经纬度网格；`xorg`、`yorg`、`delta` 单位为度 |
| `proj_id=1` | Lambert 等角圆锥投影；`delta` 单位为米 |
| `xorg`, `yorg` | 根网格西南角 |
| `ref_lat`, `ref_lon` | 投影参考点 |
| `truelat1`, `truelat2` | 标准纬线 |
| `is_global` | 根 domain 是否使用全球周期与极点拓扑 |

`proj_id=1` 时 `is_global` 固定为 `.false.`。

## 3. 时间与物理状态

### `&time`

| 字段 | 含义 |
|---|---|
| `start_time` | `YYYYMMDDHH` 格式的起始时间 |
| `run_minutes`, `run_hours`, `run_days` | 积分时长，可组合使用 |
| `dt` | 根 domain 时间步，单位秒 |
| `restart` | restart 运行请求标志 |

`start_time` 只有小时精度，因此模式从整点开始。总时长必须是 `dt` 的整数倍，否则配置解析失败。

### `&physics`

| 字段 | 含义 | 约束 |
|---|---|---|
| `nhalo` | 水平 halo 宽度 | 正整数 |
| `twindow` | `chem3d` 保留的化学时间层数 | 正整数 |

### 时间关系与约束

设开始时刻为 `t0=start_time`，配置的总时长为 `T_run`，则模拟终点为：

```text
t_end = t0 + T_run
```

根 domain 执行 `nt=T_run/dt` 个时间步。第 `i` 个根时间步积分区间为：

```text
[t0 + i×dt, t0 + (i+1)×dt),  i = 0, 1, ..., nt-1
```

因此，模式实际从 `t0` 积分到 `t_end`，不会多积分一个小时。为计算最后一个时间步，程序可能读取位于 `t_end` 或 `t_end` 之后的气象文件；该文件只提供插值端点，不会延长模拟时间。

各时间间隔必须满足：

| 关系 | 是否强制 | 原因 |
|---|---|---|
| `T_run / dt` 为整数 | 是 | 保证模拟准确结束在 `t_end` |
| `mete_timedelta / dt` 为整数 | 是 | 保证根时间步准确命中气象输入时次 |
| `output_timedelta / dt` 为整数 | 是 | 保证输出时刻与模式状态时刻重合 |
| `3600 / dt` 为整数 | 是 | 当前边界和排放清单在整点更新 |
| `T_run / output_timedelta` 为整数 | 建议 | 使输出序列完整；不是模式积分的必要条件 |

子 domain 的时间步 `dts` 由父子网格比逐级缩小。当前平流 driver 根据局地风速和网格尺度自动细分子步，水平扩散 driver 根据局地扩散系数和网格尺度自动细分子步，使实际执行显式输送 kernel 的时间步满足相应 CFL 条件。接入新的显式算法时，如果 driver 不负责细分子步，传入 kernel 的时间步必须直接满足该算法的 CFL 条件。

#### 气象数据时间

第一份气象文件必须对应 `t0`。后续文件时次为：

```text
t0, t0 + mete_timedelta, t0 + 2×mete_timedelta, ...
```

应准备到第一个不早于 `t_end` 的气象时次。模式保留相邻两个气象时次，并把标准气象场线性插值到每个 domain 子步的开始时刻。`start_time` 必须与实际存在的气象文件时次一致；例如三小时间隔的数据通常从 `00`、`03`、`06` 等时次开始。

#### 排放清单时间

当前排放清单每个整点更新一次。时间戳为 `HH:00` 的清单用于区间 `[HH:00, HH+1:00)`，区间内保持不变。对于模拟区间 `[t0,t_end)`，需要准备从 `t0` 开始、所有满足“清单时刻小于 `t_end`”的整点文件。

`emis_file` 包含 `%Y%m%d%H` 等时间占位符时，每个整点解析为对应时次的文件；不包含时间占位符时，同一个清单文件会在所有整点重复使用。缺失的排放文件会触发警告，并由确定性 MOCK 排放替代。

#### 输出时间

模式从 `t0` 起，每隔 `output_timedelta` 写出一次快照。当前输出时次满足：

```text
t_output = t0 + k×output_timedelta,  t_output <= t_end
```

`t0` 文件是积分开始前的初始快照。后续文件在所有 domain 完成相应时间步后写出，表示该时刻的积分结果。只有 `T_run` 是 `output_timedelta` 的整数倍时，`t_end` 才是计划输出时刻并生成终点文件。化学浓度是 `t_output` 的瞬时状态；同一文件中的标准气象场已插值到 `t_output`，诊断气象量也由该时刻的标准场计算，因此浓度和气象时间匹配。当前输出不是时间平均值。

推荐将 `output_timedelta` 设为 3600 秒。需要观察快速变化时可使用更短间隔，但仍须为 `dt` 的整数倍；当间隔小于一小时时，`out_file` 应包含 `%M`，避免同一小时内的文件重名。

例如，`start_time=2024010100`、运行 2 小时、`dt=600` 秒，且气象和输出间隔均为 3600 秒时：

| 数据或过程 | 实际时刻或区间 |
|---|---|
| 模式积分 | `2024-01-01 00:00` 至 `02:00`，共 12 步 |
| 所需气象时次 | `00:00`、`01:00`、`02:00` |
| 所需逐小时排放清单 | `00:00`、`01:00` |
| 瞬时输出 | `00:00`（初始状态）、`01:00`、`02:00` |

其中 `02:00` 气象场既是最后一小时的插值端点，也与 `02:00` 浓度积分结果一起写出。模式不会继续积分 `02:00` 至 `03:00`。

## 4. 化学、气象和排放输入

### `&chem`

| 字段 | 允许值或含义 |
|---|---|
| `chem_meta_file` | 化学变量 CSV 路径 |
| `ic_file` | 统一化学初值 NetCDF 模板；文件缺失时初始化为零场 |
| `bc_file` | 统一化学外边界文件模板 |
| `emis_file` | 统一排放清单 NetCDF 模板 |
| `emis_nlev` | 排放文件中的垂直层数 |

初值、边界和排放不设数据源选择字段，各自只使用一种 FlexCTM 文件契约。排放文件缺失时，模式打印警告并生成确定性 MOCK 排放，便于无业务清单的开发测试。

排放 NetCDF 维度名为 `x`、`y`、`z`；每个排放变量的名称与 `meta/species.csv` 中对应化学变量相同。`emis_nlev` 不得大于模式 `nlev`，未覆盖的模式层保持为零。

### `&mete`

| 字段 | 允许值或含义 |
|---|---|
| `mete_table_file` | FlexCTM 标准气象变量 CSV |
| `mete_mapping_file` | 当前数据集到标准变量的映射 CSV |
| `mete_source` | `wrf` 或测试用 `mock` |
| `mete_file` | 气象文件名模板 |
| `mete_timedelta` | 相邻气象输入时次的间隔，单位秒；必须是 `dt` 的整数倍 |

WRF 输入必须同时给出 `mete_mapping_file`。气象是唯一保留数据源分派的输入；新数据集必须转换为 `mete.standard.csv` 定义的标准场。主模式保存相邻两个气象时次，并在每个 domain 子步上线性插值。

### 文件名模板

| 占位符 | 替换值 |
|---|---|
| `[DOMAIN]` | 一基 domain 标识 |
| `%Y`, `%m`, `%d`, `%H`, `%M`, `%S` | 当前模式时间的年、月、日、时、分、秒 |

## 5. 变量元数据

### 化学变量表

`meta/species.csv` 每行有 16 列：

```text
name, phase, role,
transported, advected, diffused,
read_initial, read_boundary, read_emission,
use_chemistry, dry_deposition, wet_deposition,
write_output, unit, molar_mass, description
```

布尔列只接受 `true` 或 `false`。`name` 必须唯一；参与平流或扩散的变量必须同时设置 `transported=true`。

### 标准气象变量表

`meta/mete.standard.csv` 定义数值过程可见的标准气象变量：

```text
name, ndim, category, output, unit, description
```

- `ndim` 只允许 2 或 3；
- `category=standard` 由气象数据集接口提供；
- `category=diagnostic` 由 FlexCTM 的公共气象诊断计算；
- `output` 只允许 `true` 或 `false`，逐变量控制是否写入模式输出。

`meta/mete.wrf.csv` 将 WRF 原始变量映射到 `category=standard` 的变量：

```text
name, ndim, inputs, method, source_unit, target_unit, description
```

`inputs` 使用分号分隔，`raw:<name>` 表示数据集原始变量，`standard:<name>` 表示已生成的标准变量。映射按文件顺序执行，标准依赖必须在使用前生成。

## 6. 输出

### `&output`

| 字段 | 含义 |
|---|---|
| `out_file` | 瞬时化学场和同一时刻气象场的 NetCDF 文件模板 |
| `output_timedelta` | 相邻输出时次的间隔，单位秒；默认 3600 |
| `static_grid_file` | 静态网格 NetCDF 文件模板 |

化学输出由 `meta/species.csv` 的 `write_output` 逐变量控制；气象输出由 `meta/mete.standard.csv` 的 `output` 逐变量控制。模式每次初始化都写出静态网格，其中包含 `mlat`、`mlon`、`area` 和 `terrain`。

NetCDF 数值类型与模式精度一致：real64 写为 `NF90_DOUBLE`，real32 写为 `NF90_FLOAT`。并行输出只写局地有效区，不写 halo。
