# FlexCTM

FlexCTM 是面向区域与全球空气质量模拟的高度解耦合的化学输送模式。主仓负责网格生成、模式状态、时间推进和输入输出；MPI 通信、地图投影、平流、扩散和边界层参数计算等由独立软件包提供。

## 前置条件

构建前需要准备：

- Fortran 编译器；
- MPI Fortran 编译器；
- 支持并行 I/O 的 NetCDF C 和 NetCDF Fortran；
- fpm、Make 或 CMake 中至少一种构建工具。

以下命令按 GNU Fortran、Open MPI 和可用的 `nf-config` 编写。依赖源码统一保存在 `build/dependencies/`；已有完整依赖不会重复下载。

## 1. fpm：推荐

fpm 自动发现 `src/`、`app/` 和 `test/`，是日常开发和单元测试的首选方式。

先准备 FlexCTM 软件包依赖，并设置 MPI/NetCDF 参数：

```bash
bash utils/dependencies # fpm也会自动下载依赖，目前配置的fpm.toml不支持

FPM_FC=$(mpifort --showme:command)
FPM_FLAGS="$(mpifort --showme:compile) $(nf-config --fflags) -ffree-line-length-none"
FPM_LINK_FLAGS="$(mpifort --showme:link) $(nf-config --flibs)"
```

### Release、Debug 和单元测试

```bash
fpm build --profile release --compiler "$FPM_FC" \
  --flag "$FPM_FLAGS" --link-flag "$FPM_LINK_FLAGS"

fpm build --profile debug --compiler "$FPM_FC" \
  --flag "$FPM_FLAGS" --link-flag "$FPM_LINK_FLAGS"

fpm test --profile debug --compiler "$FPM_FC" \
  --flag "$FPM_FLAGS" --link-flag "$FPM_LINK_FLAGS"
```

### 浮点精度

real64 是默认精度，不需要额外宏。real32 必须同时切换主模式和四个数值依赖：

```bash
FPM_REAL32_FLAGS="$FPM_FLAGS -DFLEXCTM_REAL32 -DADVECTION_REAL32 \
-DDIFFUSION_REAL32 -DPROJECTION_REAL32 -DYSU_REAL32"

fpm build --profile release --compiler "$FPM_FC" \
  --flag "$FPM_REAL32_FLAGS" --link-flag "$FPM_LINK_FLAGS"

fpm build --profile debug --compiler "$FPM_FC" \
  --flag "$FPM_REAL32_FLAGS" --link-flag "$FPM_LINK_FLAGS"

fpm test --profile debug --compiler "$FPM_FC" \
  --flag "$FPM_REAL32_FLAGS" --link-flag "$FPM_LINK_FLAGS"
```

运行 MOCK 案例：

```bash
fpm run --profile release --compiler "$FPM_FC" \
  --flag "$FPM_FLAGS" --link-flag "$FPM_LINK_FLAGS" \
  --runner "mpirun -np 1" -- global_mock.nml
```

## 2. Make

Make 在构建前自动下载缺失的 FlexCTM 依赖，并复用 `build/dependencies/` 中已有的完整目录。

### Release、Debug 和单元测试

```bash
make release PRECISION=real64
make debug PRECISION=real64
make test PRECISION=real64
```

Make 会优先检测 Intel MPI 的 `mpiifort`，否则使用 Open MPI 的
`mpifort`。也可以显式指定工具链：

```bash
make release PRECISION=real64 COMPILER=intel FC=mpiifort
make release PRECISION=real64 COMPILER=gnu FC=mpifort
```

Make 产物统一位于：

```text
build/make/<release|debug>/<real64|real32>/
├── obj/                   FlexCTM 目标文件
├── mod/                   FlexCTM module 文件
├── dependencies/<name>/   依赖的目标文件、module 和静态库
├── tests/                 `make test` 的 fpm Debug 产物
├── lib/libFlexCTM.a
└── bin/FlexCTM.exe
```

real32 使用同一组命令，只需修改精度参数：

```bash
make release PRECISION=real32
make debug PRECISION=real32
make test PRECISION=real32
```

运行：

```bash
mpirun -np 1 build/make/release/real64/bin/FlexCTM.exe global_mock.nml
```

`make test` 调用 fpm 的 Debug 测试配置；`PRECISION` 会同步传给所有数值依赖。

## 3. CMake

CMake 检查 `build/dependencies/`，只下载缺失依赖。依赖源码由不同 CMake 配置共享，编译产物保存在各自的 binary directory，互不覆盖。

### real64 Release

```bash
cmake -S . -B build/cmake/release \
  -DCMAKE_Fortran_COMPILER=mpifort \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTING=ON
cmake --build build/cmake/release --parallel 2
ctest --test-dir build/cmake/release --output-on-failure
```

### real64 Debug

```bash
cmake -S . -B build/cmake/debug \
  -DCMAKE_Fortran_COMPILER=mpifort \
  -DCMAKE_BUILD_TYPE=Debug \
  -DBUILD_TESTING=ON
cmake --build build/cmake/debug --parallel 2
ctest --test-dir build/cmake/debug --output-on-failure
```

### real32 Release、Debug 和单元测试

在独立目录配置，并增加 `FLEXCTM_REAL32=ON`：

```bash
cmake -S . -B build/cmake/real32-release \
  -DCMAKE_Fortran_COMPILER=mpifort \
  -DCMAKE_BUILD_TYPE=Release \
  -DFLEXCTM_REAL32=ON \
  -DBUILD_TESTING=ON
cmake --build build/cmake/real32-release --parallel 2
ctest --test-dir build/cmake/real32-release --output-on-failure

cmake -S . -B build/cmake/real32-debug \
  -DCMAKE_Fortran_COMPILER=mpifort \
  -DCMAKE_BUILD_TYPE=Debug \
  -DFLEXCTM_REAL32=ON \
  -DBUILD_TESTING=ON
cmake --build build/cmake/real32-debug --parallel 2
ctest --test-dir build/cmake/real32-debug --output-on-failure
```

CMake 可执行文件位于 `<binary-directory>/bin/FlexCTM.exe`。例如：

```bash
mpirun -np 1 build/cmake/release/bin/FlexCTM.exe global_mock.nml
```

## MOCK 案例

`global_mock.nml` 使用 `360 × 180 × 20` 的一度全球网格，根时间步为 600 秒，积分 120 分钟。气象场由确定性 MOCK 接口生成；初值文件为空时使用零场；排放文件缺失时自动生成确定性 MOCK 排放并打印提示。

案例从 `2024-01-01 00:00` 开始，在每个整点写出文件：

```text
flexctm_global_mock_d01_2024010100.nc
flexctm_global_mock_d01_2024010101.nc
static_meta_d01.nc
```


MOCK 案例用于构建验证、单元测试和数值回归，不代表业务输入格式。

## 开发文档

文档位于 `pages/`：

1. [布局约定](pages/project.md)
2. [总体架构](pages/architecture.md)
3. [数据结构](pages/data-structures.md)
4. [接口规则](pages/interfaces.md)
5. [配置与输入](pages/configuration.md)
6. [编码规则约定](pages/fortran-style.md)

## 生成文档

API 文档由 FORD 生成，架构图需要 Graphviz。安装这两个文档工具后执行：

```bash
make docs
```

站点生成到 `_site/`。在线版本为 [FlexCTM 文档](https://flexctm.github.io/FlexCTM/)。

## License

GPL-3.0-or-later。
