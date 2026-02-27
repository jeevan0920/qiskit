# This code is part of Qiskit.
#
# (C) Copyright IBM 2017.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at https://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

ifneq ($(OS), Windows_NT)
	OS := $(shell uname -s)
endif

.PHONY: default ruff env lint lint-incr style black test test_randomized pytest pytest_randomized test_ci coverage coverage_erase clean \
        docker-build docker-run docker-shell docker-test docker-test-rust docker-clean docker-logs docker-stop docker-rebuild-rust docker-full-test docker-help help

default: ruff style lint-incr test ;

# Display help information
help:
	@echo "Qiskit Development Targets:"
	@echo ""
	@echo "Python code quality:"
	@echo "  make lint              - Run pylint and verify headers"
	@echo "  make lint-incr         - Run pylint on changed files only"
	@echo "  make ruff              - Run ruff linter"
	@echo "  make style             - Check code style with black"
	@echo "  make black             - Apply black formatting"
	@echo ""
	@echo "Testing:"
	@echo "  make test              - Run Python unit tests"
	@echo "  make test_ci           - Run tests for CI"
	@echo "  make test_randomized   - Run randomized tests"
	@echo "  make pytest            - Run tests with pytest"
	@echo "  make pytest_randomized - Run randomized pytest tests"
	@echo "  make coverage          - Generate coverage report"
	@echo "  make coverage_erase    - Erase coverage data"
	@echo ""
	@echo "C API:"
	@echo "  make c                 - Build C extension"
	@echo "  make cheader           - Build C header files"
	@echo "  make clib              - Build C library"
	@echo "  make ctest             - Run C tests"
	@echo "  make cformat           - Check C code formatting"
	@echo "  make fix_cformat       - Fix C code formatting"
	@echo "  make ccoverage         - Generate C code coverage"
	@echo "  make cclean            - Clean C build artifacts"
	@echo ""
	@echo "Docker Development (for Rust components):"
	@echo "  make docker-build      - Build Docker development image"
	@echo "  make docker-run        - Start Docker container"
	@echo "  make docker-shell      - Enter interactive shell"
	@echo "  make docker-rebuild-rust - Rebuild Rust after changes"
	@echo "  make docker-test       - Run Python tests"
	@echo "  make docker-test-rust  - Run Rust tests"
	@echo "  make docker-logs       - View container logs"
	@echo "  make docker-stop       - Stop the container"
	@echo "  make docker-clean      - Remove all Docker resources"
	@echo "  make docker-full-test  - Full build + test cycle"
	@echo "  make docker-help       - Show Docker-specific help"
	@echo ""
	@echo "Environment:"
	@echo "  make env               - Set up Anaconda environment"
	@echo "  make clean             - Clean all build artifacts"
	@echo ""

# Dependencies need to be installed on the Anaconda virtual environment.
env:
	if test $(findstring qiskitenv, $(shell conda info --envs | tr '[:upper:]' '[:lower:]')); then \
		bash -c "source activate Qiskitenv;pip install -r requirements.txt"; \
	else \
		conda create -y -n Qiskitenv python=3; \
		bash -c "source activate Qiskitenv;pip install -r requirements.txt"; \
	fi;

# Ignoring generated ones with .py extension.
lint:
	pylint -rn qiskit test tools
	tools/verify_headers.py qiskit test tools
	tools/find_optional_imports.py
	tools/find_stray_release_notes.py
	tools/verify_images.py

# Only pylint on files that have changed from origin/main. Also parallelize (disables cyclic-import check)
lint-incr:
	-git fetch -q https://github.com/Qiskit/qiskit-terra.git :lint_incr_latest
	tools/pylint_incr.py -j4 -rn -sn --paths :/qiskit/*.py :/test/*.py :/tools/*.py
	tools/verify_headers.py qiskit test tools
	tools/find_optional_imports.py
	tools/verify_images.py

ruff:
	ruff qiskit test tools setup.py

style:
	black --check qiskit test tools setup.py docs/conf.py

black:
	black qiskit test tools setup.py docs/conf.py

# Use the -s (starting directory) flag for "unittest discover" is necessary,
# otherwise the QuantumCircuit header will be modified during the discovery.
test:
	@echo ================================================
	@echo Consider using tox as suggested in the CONTRIBUTING.MD guideline. For running the tests as the CI, use test_ci
	@echo ================================================
	python3 -m unittest discover -s test/python -t . -v
	@echo ================================================
	@echo Consider using tox as suggested in the CONTRIBUTING.MD guideline. For running the tests as the CI, use test_ci
	@echo ================================================

# Use pytest to run tests
pytest:
	pytest test/python

# Use pytest to run randomized tests
pytest_randomized:
	pytest test/randomized

test_ci:
	QISKIT_TEST_CAPTURE_STREAMS=1 stestr run

test_randomized:
	python3 -m unittest discover -s test/randomized -t . -v

coverage:
	coverage run --source qiskit -m unittest discover -s test/python -q
	coverage report

coverage_erase:
	coverage erase

clean: coverage_erase ;

# ==============================================================================
# Variables that can be set/modified to modify the C builds.
# ==============================================================================

# Include files that are manually written, relative to the `include` directory
# (both in and out).
C_INCLUDE_FILES_MANUAL=\
	qiskit/attributes.h \
	qiskit/complex.h \
	qiskit/version.h
# Include files that are generated by a build script, relative to the output
# `include` directory.
C_INCLUDE_FILES_GENERATED=\
	qiskit.h
# Directories used in the structure of the include-files output.
C_DIR_INCLUDE_INTERNAL=qiskit

# Output directories.
C_DIR_OUT=dist/c
C_DIR_OUT_LIB=$(C_DIR_OUT)/lib
C_DIR_OUT_INCLUDE=$(C_DIR_OUT)/include
C_DIR_TEST=test/c
C_DIR_TEST_BUILD=test/c/build

# Input directories
C_DIR_CARGO_TARGET=target
C_DIR_SRC_INCLUDE=crates/cext/include

# ==============================================================================
# Variables that we derive from the settings above.
# ==============================================================================

ifeq ($(OS), Windows_NT)
	C_LIB_CARGO_FILENAME=qiskit_cext.dll
else ifeq ($(shell uname), Darwin)
	C_LIB_CARGO_FILENAME=libqiskit_cext.dylib
else
	# ... probably.
	C_LIB_CARGO_FILENAME=libqiskit_cext.so
endif

C_DIR_OUT_INCLUDE_ALL=$(C_DIR_OUT_INCLUDE) $(addprefix $(C_DIR_OUT_INCLUDE)/,$(C_DIR_INCLUDE_INTERNAL))

C_INCLUDE_FILES_ABS_GENERATED=$(addprefix $(C_DIR_CARGO_TARGET)/,$(C_INCLUDE_FILES_GENERATED))
C_INCLUDE_FILES_OUT_MANUAL=$(addprefix $(C_DIR_OUT_INCLUDE)/,$(C_INCLUDE_FILES_MANUAL))
C_INCLUDE_FILES_OUT_GENERATED=$(addprefix $(C_DIR_OUT_INCLUDE)/,$(C_INCLUDE_FILES_GENERATED))

C_LIBQISKIT_OUT=$(C_DIR_OUT_LIB)/$(subst _cext,,$(C_LIB_CARGO_FILENAME))

# ==============================================================================
# Recipes for the C components.
# ==============================================================================

.PHONY: cformat fix_cformat
# Run clang-format (does not apply any changes)
cformat:
	bash tools/run_clang_format.sh
# Apply clang-format changes
fix_cformat:
	bash tools/run_clang_format.sh apply

# Abstraction over calling Cargo to build the C extension in "standalone" C
# mode.  This _also_ builds the C header file as a side-effect into
# `target/qiskit.h`.  Recipes that use this as a prerequisite should ensure they
# set `C_LIB_CARGO_FLAGS` to choose the build profile.  The `C_LIB_RUSTC_FLAGS`
# variable can also be set to add additional logic (like coverage instructions).
#
# Typically, downstream recipes should depend on `build-clib-release` or `build-clib-dev`
# instead.
.PHONY: build-clib build-clib-release build-clib-dev
build-clib:
	cargo rustc -p qiskit-cext --crate-type cdylib ${C_LIB_CARGO_FLAGS} -- ${C_LIB_RUSTC_FLAGS}
build-clib-release: C_LIB_CARGO_FLAGS=--release
build-clib-release: build-clib
build-clib-dev: C_LIB_CARGO_FLAGS=--profile dev
build-clib-dev: build-clib
# This is the minimal amount of work we can do that builds the generated header
# file(s) (by force running the build script of `qiskit-cext`).  You do not need
# to run this rule if you also depend on `build-clib`, but it doesn't hugely
# hurt.  Use the `cheader` rule to install these files into the correct place.
.PHONY: build-cheader
build-cheader:
	cargo check -p qiskit-cext

# Catch-all directory-creation rule.
$(C_DIR_OUT_LIB) $(C_DIR_OUT_INCLUDE_ALL):
	mkdir -p $@

$(C_INCLUDE_FILES_ABS_GENERATED): build-cheader
$(C_INCLUDE_FILES_OUT_MANUAL): $(C_DIR_OUT_INCLUDE)/%.h: $(C_DIR_SRC_INCLUDE)/%.h | $(C_DIR_OUT_INCLUDE_ALL)
	cp $< $@
$(C_INCLUDE_FILES_OUT_GENERATED): $(C_DIR_OUT_INCLUDE)/%.h: $(C_DIR_CARGO_TARGET)/%.h | $(C_DIR_OUT_INCLUDE_ALL)
	cp $< $@

.PHONY: cheader
cheader: $(C_INCLUDE_FILES_OUT_GENERATED) $(C_INCLUDE_FILES_OUT_MANUAL)
# `clib` and `clib-dev` are conflicting rules - they both attempt to "install" the
# shared library into the output `lib` directory, but they differ between release
# and dev mode.
.PHONY: clib
clib: build-clib-release | $(C_DIR_OUT_LIB)
	cp $(C_DIR_CARGO_TARGET)/release/$(C_LIB_CARGO_FILENAME) $(C_LIBQISKIT_OUT)
.PHONY:
clib-dev: build-clib-dev | $(C_DIR_OUT_LIB)
	cp $(C_DIR_CARGO_TARGET)/debug/$(C_LIB_CARGO_FILENAME) $(C_LIBQISKIT_OUT)
.PHONY: c
c: cheader clib

.PHONY: ctest
# Use ctest to run C API tests.
ctest: cheader build-clib-dev
# `-S` specifies the source (including the `CMakeLists.txt` file, `-B` is where
# to put the build files, including the generated CMake stuff.  See the
# `CMakeLists.txt` file for the build variables.
	cmake -S$(C_DIR_TEST) -B$(C_DIR_TEST_BUILD) \
		-DCARGO_LIB_DIR=$(abspath $(C_DIR_CARGO_TARGET))/debug \
		-DQISKIT_INCLUDE_PATH=$(abspath $(C_DIR_OUT_INCLUDE))
# Actually build the test.
	cmake --build $(C_DIR_TEST_BUILD)
# -V ensures we always produce a logging output to indicate the subtests
# -C Debug is needed for windows to work, if you don't specify Debug (or
# Release) explicitly ctest doesn't run on windows
	ctest -V -C Debug --test-dir $(C_DIR_TEST_BUILD)

.PHONY: ccoverage
ccoverage: C_LIB_RUSTC_FLAGS=-Cinstrument-coverage
ccoverage: ctest

.PHONY: cclean
cclean:
	rm -rf $(C_DIR_OUT) $(C_DIR_TEST_BUILD) $(C_INCLUDE_FILES_ABS_GENERATED)
	cargo clean --package qiskit-cext

# ==============================================================================
# Docker Development Targets
# ==============================================================================
# These targets simplify development workflow when working with Rust components.
# They ensure consistent Python (3.12) and Rust toolchain versions across
# all developers' machines.

.PHONY: docker-build docker-run docker-shell docker-test docker-test-rust \
        docker-clean docker-logs docker-stop docker-rebuild-rust docker-full-test \
        docker-help

# Build the Docker development image
docker-build:
	@echo "Building Qiskit development Docker image..."
	docker-compose -f docker-compose.dev.yml build --no-cache qiskit-dev

# Start the Docker container in background
docker-run:
	@echo "Starting Qiskit development container..."
	docker-compose -f docker-compose.dev.yml up -d qiskit-dev

# Interactive shell in the container
docker-shell: docker-run
	@echo "Entering Qiskit development container (Python 3.12)..."
	docker-compose -f docker-compose.dev.yml exec qiskit-dev /bin/bash

# Rebuild Rust components inside container
docker-rebuild-rust:
	@echo "Rebuilding Rust components in container..."
	docker-compose -f docker-compose.dev.yml exec qiskit-dev \
		python setup.py build_rust --inplace --release

# Run specific Python test inside container
docker-test: docker-rebuild-rust
	@echo "Running Python tests in container..."
	docker-compose -f docker-compose.dev.yml exec qiskit-dev \
		tox --skip-pkg-install -epy312 -- test.python.circuit.test_control_flow.TestAddingControlFlowOperations.test_for_loop_op_with_reused_parameter_assign_parameters

# Run Rust tests inside container
docker-test-rust: docker-rebuild-rust
	@echo "Running Rust tests in container..."
	docker-compose -f docker-compose.dev.yml exec qiskit-dev \
		tox --skip-pkg-install -erust

# View container logs
docker-logs:
	docker-compose -f docker-compose.dev.yml logs -f qiskit-dev

# Stop the container
docker-stop:
	docker-compose -f docker-compose.dev.yml down

# Clean everything (remove container and image)
docker-clean: docker-stop
	@echo "Cleaning Docker resources..."
	docker-compose -f docker-compose.dev.yml down -v
	docker rmi qiskit-qiskit-dev 2>/dev/null || true

# All-in-one: build + run + test
docker-full-test: docker-build docker-run docker-test
	@echo "✅ Docker full test cycle complete!"

# Docker help
docker-help:
	@echo "Qiskit Docker Development Targets:"
	@echo ""
	@echo "Getting started:"
	@echo "  make docker-build       - Build Docker development image (first time only)"
	@echo "  make docker-run         - Start Docker container in background"
	@echo "  make docker-shell       - Enter interactive shell in container"
	@echo ""
	@echo "Building and testing (inside container):"
	@echo "  make docker-rebuild-rust - Rebuild Rust components (after editing .rs files)"
	@echo "  make docker-test        - Run Python tests"
	@echo "  make docker-test-rust   - Run Rust tests"
	@echo ""
	@echo "Container management:"
	@echo "  make docker-logs        - View container logs"
	@echo "  make docker-stop        - Stop the container"
	@echo "  make docker-clean       - Remove all Docker resources"
	@echo "  make docker-full-test   - Full build + run + test cycle"
	@echo ""
	@echo "Quick workflow:"
	@echo "  1. make docker-build"
	@echo "  2. make docker-shell"
	@echo "  3. Edit code on your host machine"
	@echo "  4. Inside container: python setup.py build_rust --inplace --release"
	@echo "  5. Inside container: tox --skip-pkg-install -epy312 -- <test>"
	@echo "  6. make docker-stop (when done)"
