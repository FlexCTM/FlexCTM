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

总时长必须是 `dt` 的整数倍，否则配置解析失败。

### `&physics`

| 字段 | 含义 | 约束 |
|---|---|---|
| `nhalo` | 水平 halo 宽度 | 正整数 |
| `twindow` | `chem3d` 保留的化学时间层数 | 正整数 |

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
| `mete_timedelta` | 相邻气象输入时次的间隔，单位秒 |

WRF 输入必须同时给出 `mete_mapping_file`。气象是唯一保留数据源分派的输入；新数据集必须转换为 `mete.standard.csv` 定义的标准场。主模式保存相邻两个气象时次，并在每个 domain 子步上线性插值。

### 文件名模板

| 占位符 | 替换值 |
|---|---|
| `[DOMAIN]` | 一基 domain 标识 |
| `%Y`, `%m`, `%d`, `%H` | 当前模式时间的年、月、日、时 |

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
| `out_file_name` | 化学场和气象诊断的 NetCDF 文件模板 |
| `static_grid_file` | 静态网格 NetCDF 文件模板 |

化学输出由 `meta/species.csv` 的 `write_output` 逐变量控制；气象输出由 `meta/mete.standard.csv` 的 `output` 逐变量控制。模式每次初始化都写出静态网格，其中包含 `mlat`、`mlon`、`area` 和 `terrain`。

NetCDF 数值类型与模式精度一致：real64 写为 `NF90_DOUBLE`，real32 写为 `NF90_FLOAT`。并行输出只写局地有效区，不写 halo。
