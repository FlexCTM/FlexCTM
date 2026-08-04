---
title: 接口规则
---

# 接口规则

接口的目标是让文件格式、主模式状态和底层数值实现可以独立演化。

## 1. 主接口链

| 输入或过程 | 公开入口 | 主要结果 |
|---|---|---|
| namelist | `load_config` | `config_type` |
| 化学元数据 | `load_chem_table` | `chem_table_type` |
| 气象元数据 | `load_mete_table`, `load_mete_mapping_table` | `mete_table_type`, `mete_mapping_table_type` |
| 化学初值 | `initialize_chemistry` | `block_type%chem3d` |
| 气象场 | `read_mete_static`, `read_mete_field` | `terrain`, `mete2d`, `mete3d` |
| 排放 | `update_emission` | `block_type%emis3d` |
| 外边界 | `read_domain_boundary` | `block_type%edges(:)%bc` |
| 平流、扩散 | `drive_*` | 原地更新 `chem3d` |
| NetCDF 输出 | `write_static_output`, `write_model_output` | 静态网格或当前时刻模式快照 |

数据源入口可接收 `process_type`、`domain_type`、`tile_type` 和 `block_type`，因为它们需要将全局文件切成当前 rank 的有效区。

## 2. I/O 模块的输出契约

外部数据进入 `block_type` 前必须完成：

1. 名称映射：转为 FlexCTM 标准变量名；
2. 网格定位：转为质量网格或约定的交错位置；
3. 单位归一：转为元数据中的标准单位；
4. shape 检查：与 domain 水平尺寸、垂直层和变量数一致；
5. 错误上下文：失败信息包含操作、文件和变量名。

气象数据集接口实现相同的 `read_mete_field` 契约。数值过程不使用 WRF、GFS 等数据集专有变量。只有气象输入保留可扩展数据源接口；化学初值、边界和排放使用各自唯一的文件契约。

业务排放清单只采用一种 NetCDF 契约：水平维度为 `x, y`，垂直维度为 `z`，变量名与 `meta/species.csv` 中 `read_emission=true` 的 `name` 一致。读取后存入 `emis3d(x, y, z, chemical_variable)`；文件缺失时由同一入口生成 MOCK 排放。

## 3. driver 与底层 kernel

driver 是主模式与独立数值包之间的适配层。driver 可以读写 `block_type`，并负责：

- 选择有效区、变量子集和时间层；
- 按 kernel 契约准备 halo 和 domain 边界；
- 适配数组顺序、网格位置和单位；
- 将 kernel 结果写回模式状态。

底层 kernel 只接收计算必需的数组和标量。公开过程必须在注释和测试中确定下列契约：

| 契约 | 要求 |
|---|---|
| shape | 每一维的物理含义、是否包含 halo |
| kind | 统一使用包公开的 `fp` |
| 单位 | 输入、输出和变换量的单位 |
| `intent` | 明确只读、只写或原地更新 |
| 边界 | 调用前需要的 halo 宽度和物理边界 |
| 失败 | 可恢复错误返回状态，不可恢复错误在应用边界终止 |

底层包不得 `use mod_block`、读取 namelist 或打开业务 NetCDF 文件。

## 4. 物理化学机制的对象边界

无状态计算使用 module procedure。当一个机制实例需要在多个时间步之间保留反应表、物种映射、Jacobian 结构或求解器工作区时，使用派生类型表达 `init/advance/clear` 生命周期。

统一的运行时多态接口只从已有机制的共同需求提取。机制对象保存自身参数和工作区，不保存指向整个 `block_type` 的长期引用。

## 5. 错误处理

- 解析器在使用数据前检查名称唯一性、枚举值、布尔值和依赖关系；
- NetCDF 调用统一通过 `check_netcdf`，不忽略状态码；
- 可复用的底层过程优先返回 `stat` 和 `errmsg`；
- 应用层无法继续时通过 `fatal_error` 给出唯一、完整的失败信息。
