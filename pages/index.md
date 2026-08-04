---
title: FlexCTM 开发文档
author: Linhong Xiao
ordered_subpage: project.md
ordered_subpage: architecture.md
ordered_subpage: data-structures.md
ordered_subpage: interfaces.md
ordered_subpage: configuration.md
ordered_subpage: fortran-style.md
---

# FlexCTM 开发文档

FlexCTM 是用 Fortran 编写的模块化化学输送模式框架，支持区域和全球结构化网格。主仓负责配置、数据接口、模式状态和时间推进；MPI 通信、投影和数值算法由独立软件包提供。

构建、运行和 MOCK 案例统一放在项目 `README.md`。本站只说明开发者需要维护的软件契约。

## 阅读顺序

1. [文件约定](project.html)：文件命名、放置规则和测试组织；
2. [总体架构](architecture.html)：分层、数据流和运行时序；
3. [数据结构](data-structures.html)：`block_type` 及其数组布局；
4. [接口规则](interfaces.html)：I/O、状态容器、driver 和底层算法的边界；
5. [配置文件](configuration.html)：namelist、元数据和文件约定；
6. [编码习惯](fortran-style.html)：主仓的最小编码约定。

