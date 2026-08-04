TARGET := FlexCTM
BUILD ?= release
PRECISION ?= real64
.DEFAULT_GOAL := all

# Compiler and external libraries
AR := ar
NON_BUILD_GOALS := clean docs
ifneq ($(strip $(MAKECMDGOALS)),)
  ifeq ($(strip $(filter-out $(NON_BUILD_GOALS),$(MAKECMDGOALS))),)
    SKIP_COMPILER_CONFIG := yes
  endif
endif

ifneq ($(SKIP_COMPILER_CONFIG),yes)
ifeq ($(origin COMPILER), undefined)
  ifneq ($(shell command -v mpiifort 2>/dev/null),)
    COMPILER := intel
    FC := mpiifort
  else ifneq ($(shell command -v mpifort 2>/dev/null),)
    COMPILER := gnu
    FC := mpifort
  else
    $(error No MPI Fortran compiler found: install mpiifort or mpifort)
  endif
endif

ifeq ($(COMPILER),intel)
  ifeq ($(origin FC),default)
    FC := mpiifort
  endif
  COMPILER_FFLAGS := -no-wrap-margin
  FPM_COMPILER := $(FC)
  DEBUG_FFLAGS := -O0 -g -traceback -check all
else ifeq ($(COMPILER),gnu)
  ifeq ($(origin FC),default)
    FC := mpifort
  endif
  COMPILER_FFLAGS := -ffree-line-length-none
  FPM_COMPILER := $(shell $(FC) --showme:command 2>/dev/null)
  MPI_FFLAGS := $(shell $(FC) --showme:compile 2>/dev/null)
  MPI_LDFLAGS := $(addprefix -L,$(shell $(FC) --showme:libdirs 2>/dev/null))
  DEBUG_FFLAGS := -O0 -g -fbacktrace -fcheck=all
else
  $(error Unsupported COMPILER='$(COMPILER)'; use intel or gnu)
endif

NETCDF_FFLAGS := $(shell nf-config --fflags)
# Debian/Ubuntu install the parallel C library in a non-default directory while
# retaining the common NetCDF Fortran module.  Put that directory before the
# paths emitted by nf-config when the caller requests the MPI implementation.
NETCDF_MPI_LIBDIR ?=
NETCDF_MPI_LDFLAGS := $(if $(NETCDF_MPI_LIBDIR),-L$(NETCDF_MPI_LIBDIR) -Xlinker -rpath -Xlinker $(NETCDF_MPI_LIBDIR))
NETCDF_LDFLAGS := $(NETCDF_MPI_LDFLAGS) $(shell nf-config --flibs)
FFLAGS := $(COMPILER_FFLAGS) $(NETCDF_FFLAGS)
LDFLAGS := $(NETCDF_LDFLAGS)

FPM_FFLAGS := $(COMPILER_FFLAGS) $(MPI_FFLAGS) $(NETCDF_FFLAGS)
FPM_LDFLAGS := $(MPI_LDFLAGS) $(NETCDF_LDFLAGS)
endif

ifeq ($(PRECISION),real32)
  PRECISION_FLAGS := -DFLEXCTM_REAL32 -DADVECTION_REAL32 -DDIFFUSION_REAL32 \
                     -DPROJECTION_REAL32 -DYSU_REAL32
else ifeq ($(PRECISION),real64)
  PRECISION_FLAGS :=
else
  $(error Unsupported PRECISION='$(PRECISION)'; use real32 or real64)
endif
FFLAGS += $(PRECISION_FLAGS)
FPM_FFLAGS += $(PRECISION_FLAGS)

ifeq ($(BUILD),debug)
  FFLAGS += $(DEBUG_FFLAGS)
else ifeq ($(BUILD),release)
  FFLAGS += -O3
else
  $(error Unsupported BUILD='$(BUILD)'; use debug or release)
endif

# Source and build layout
WORK_DIR := $(CURDIR)
SRC_DIR := $(WORK_DIR)/src
APP_DIR := $(WORK_DIR)/app
BUILD_DIR := $(WORK_DIR)/build/make/$(BUILD)/$(PRECISION)
OBJ_DIR := $(BUILD_DIR)/obj
MOD_DIR := $(BUILD_DIR)/mod
LIB_DIR := $(BUILD_DIR)/lib
BIN_DIR := $(BUILD_DIR)/bin

$(shell mkdir -p $(OBJ_DIR) $(MOD_DIR) $(LIB_DIR) $(BIN_DIR))
ifeq ($(COMPILER),intel)
  FFLAGS += -module $(MOD_DIR) -I$(MOD_DIR)
else
  FFLAGS += -J$(MOD_DIR) -I$(MOD_DIR)
endif

SRCS := $(wildcard $(SRC_DIR)/*.[fF]90)
DRIVE_SRCS := $(wildcard $(SRC_DIR)/drive/*.[fF]90)
APPS := $(wildcard $(APP_DIR)/*.[fF]90)

ROOT_NAMES := $(notdir $(SRCS))
DRIVE_NAMES := $(notdir $(DRIVE_SRCS))
APP_NAMES := $(notdir $(APPS))
ROOT_OBJS := $(addprefix $(OBJ_DIR)/,$(ROOT_NAMES:%=%.o))
DRIVE_OBJS := $(addprefix $(OBJ_DIR)/,$(DRIVE_NAMES:%=%.o))
APP_OBJS := $(addprefix $(OBJ_DIR)/,$(APP_NAMES:%=%.o))
LIB_OBJS := $(ROOT_OBJS) $(DRIVE_OBJS)

EXE := $(BIN_DIR)/$(TARGET).exe
LIB := $(LIB_DIR)/lib$(TARGET).a

# FlexCTM package dependencies. Sources are downloaded once and reused by
# Make, fpm and CMake. Existing complete checkouts are never replaced.
DEPS := advection container datetime diffusion parallel projection ysu
DEP_ROOT := $(WORK_DIR)/build/dependencies
DEP_DIRS := $(addprefix $(DEP_ROOT)/,$(DEPS))
DEP_MOD_DIRS := $(foreach dep,$(DEPS),$(BUILD_DIR)/dependencies/$(dep)/obj)
DEP_LIBS := $(foreach dep,$(DEPS),$(BUILD_DIR)/dependencies/$(dep)/lib/lib$(dep).a)
FFLAGS += $(addprefix -I,$(DEP_MOD_DIRS))

$(DEP_ROOT)/%/Makefile:
	@bash utils/dependencies $*

define DEPENDENCY_RULE
.PHONY: $(1)
$(1): $(DEP_ROOT)/$(1)/Makefile
	+@$(MAKE) -C $(DEP_ROOT)/$(1) lib \
		COMPILER=$(COMPILER) FC=$(FC) BUILD=$(BUILD) PRECISION=$(PRECISION) \
		DST_DIR=$(BUILD_DIR)/dependencies/$(1)/obj \
		OUT_DIR=$(BUILD_DIR)/dependencies/$(1)/lib
endef
$(foreach dep,$(DEPS),$(eval $(call DEPENDENCY_RULE,$(dep))))

.PHONY: dependencies
dependencies: $(DEPS)

# Fortran module dependency graph for the main repository.
DEP_FILE := $(OBJ_DIR)/Makefile.lib.dep
$(shell DST_DIR=$(OBJ_DIR) ./utils/deps $(SRCS) $(DRIVE_SRCS) > $(DEP_FILE))
include $(DEP_FILE)

.PHONY: all debug release
all: $(EXE)

debug:
	@$(MAKE) BUILD=debug PRECISION=$(PRECISION) all

release:
	@$(MAKE) BUILD=release PRECISION=$(PRECISION) all

$(LIB_OBJS) $(APP_OBJS): | dependencies
$(APP_OBJS): $(LIB)

$(EXE): $(LIB) $(APP_OBJS)
	@echo "link $@"
	@$(FC) $(FFLAGS) $(APP_OBJS) $(LIB) $(DEP_LIBS) $(LDFLAGS) -o $@

$(LIB): $(LIB_OBJS)
	@echo "archive $@"
	@$(AR) crs $@ $^

$(APP_OBJS): $(OBJ_DIR)/%.o: $(APP_DIR)/%
	@echo "FC $<"
	@$(FC) $(FFLAGS) -c $< -o $@

$(ROOT_OBJS): $(OBJ_DIR)/%.o: $(SRC_DIR)/%
	@echo "FC $<"
	@$(FC) -fPIC $(FFLAGS) -c $< -o $@

$(DRIVE_OBJS): $(OBJ_DIR)/%.o: $(SRC_DIR)/drive/%
	@echo "FC $<"
	@$(FC) -fPIC $(FFLAGS) -c $< -o $@

.PHONY: run test _test docs clean gdb
run: $(EXE)
	mpirun -np 1 $(EXE) mock.nml

test:
	+@$(MAKE) BUILD=debug PRECISION=$(PRECISION) _test

_test:
	@bash utils/dependencies
	fpm test --profile debug --build-dir $(BUILD_DIR)/tests \
		--compiler $(if $(FPM_COMPILER),$(FPM_COMPILER),$(FC)) \
		--flag "$(FPM_FFLAGS)" --link-flag "$(FPM_LDFLAGS)"

docs:
	ford docs.md -o _site

gdb:
	@$(MAKE) BUILD=debug PRECISION=$(PRECISION) all
	gdb $(WORK_DIR)/build/make/debug/$(PRECISION)/bin/$(TARGET).exe

clean:
	rm -rf $(BUILD_DIR)
