---
title: 文件约定
---

# 文件约定

本章回答两个问题：新文件应放在哪里，应叫什么。构建和运行命令见项目 `README.md`。

## 1. 目录职责

```text
FlexCTM/
├── app/             主程序入口和运行编排
├── src/             模式状态、数据接口和 I/O
│   └── drive/       主模式状态到独立数值包的适配
├── test/            单元、组件和集成测试
├── meta/            变量元数据和数据集映射
├── pages/           FORD 开发文档
├── media/           文档图片
├── utils/           依赖准备和后处理工具
├── CMakeLists.txt    CMake 构建入口
├── Makefile          Make 构建入口
└── fpm.toml          fpm 包描述
```

`app/` 只组合已有接口，不实现数值 kernel。
`src/drive/` 只放需要同时理解 `block_type` 和底层算法接口的代码。

## 2. 文件与模块命名

| 对象 | 格式 | 示例 |
|---|---|---|
| Fortran 文件 | `module_<name>.f90` 或 `module_<name>.F90` | `module_meteorology_wrf.F90` |
| Fortran 模块 | `mod_<name>` | `mod_meteorology_wrf` |
| 派生类型 | `<name>_type` | `block_type` |
| driver 文件 | `src/drive/module_drive_<process>.F90` | `module_drive_adv.F90` |
| 测试文件 | 按被测职责命名 | `test/mete_csv.f90` |
| 数据集映射 | `mete.<dataset>.csv` | `mete.wrf.csv` |

需要预处理宏的 Fortran 源文件使用 `.F90`，否则使用 `.f90`。文件名和模块名保持一一对应，便于从编译错误定位源文件。

## 3. 新代码的放置判断

```text
读写外部文件？ ── 是 ──> src/ 中的数据源或 I/O 模块
        │
        否
        ↓
同时依赖 block_type 和独立数值包？
        ├── 是 ──> src/drive/
        └── 否 ──> 放入职责最接近的 src/ 模块，或独立数值包
```

数据集专有名称必须停在数据源模块内。例如 WRF 的 `PB` 和 `PHB` 由 WRF 接口处理，其他模块只看到 FlexCTM 标准变量 `P`、`dz` 和 `zt`。

## 4. 生成文件

| 来源 | 位置 |
|---|---|
| fpm 构建 | `build/` 下的 fpm 配置目录 |
| Make 构建 | `build/make/<build>/<precision>/` |
| CMake 构建 | 用户指定的 CMake binary directory |
| 下载的依赖源码 | `build/dependencies/<package>/` |
| FORD 站点 | `_site/` |

源码目录中不放 `.o`、`.mod`、静态库或可执行文件。

## 5. 测试组织

`test/` 统一管理三类测试：

| 类型 | 目标 | 示例 |
|---|---|---|
| 单元测试 | 验证纯解析、映射和小型计算 | CSV 字段、时间步数 |
| 组件测试 | 验证 `block_type`、NetCDF 和气象接口 | `test/block.f90` |
| MOCK 测试 | 用可重复的合成场验证多模块协作 | 气象、排放回退和端到端运行 |

MOCK 是测试输入，不是业务数据格式。当合成场的类型和规模增长时，可将生成器集中到专用测试包，但仍通过正式公开接口验证主模式。
