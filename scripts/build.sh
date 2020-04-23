#!/usr/bin/env bash
# Copyright (c) 2019 Trail of Bits, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# General directory structure:
#   /path/to/home/rellic
#   /path/to/home/rellic-build

SCRIPTS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
SRC_DIR=$( cd "$( dirname "${SCRIPTS_DIR}" )" && pwd )
CURR_DIR=$( pwd )
BUILD_DIR="${CURR_DIR}/rellic-build"
INSTALL_DIR=/usr/local
LLVM_VERSION=llvm40
OS_VERSION=unknown
ARCH_VERSION=unknown
BUILD_FLAGS=
USE_HOST_COMPILER=0

Z3_ARCHIVE=z3-
Z3_VERSION=4.7.1
Z3_ARCH_VERSION=x64
Z3_OS_VERSION=ubuntu-16.04

# There are pre-build versions of various libraries for specific
# Ubuntu releases.
function GetUbuntuOSVersion
{
  # Version name of OS (e.g. xenial, trusty).
  source /etc/lsb-release

  case "${DISTRIB_CODENAME}" in
    cosmic)
      # TODO(pag): Eventually make real packages for 18.10!
      OS_VERSION=ubuntu1604
      return 0
    ;;
    bionic)
      OS_VERSION=ubuntu1804
      return 0
    ;;
    xenial)
      OS_VERSION=ubuntu1604
      return 0
    ;;
    trusty)
      USE_HOST_COMPILER=1
      OS_VERSION=ubuntu1404
      return 0
    ;;
    *)
      echo "[x] Ubuntu ${DISTRIB_CODENAME} is not supported. Only xenial (16.04) and trusty (14.04) are supported."
      return 1
    ;;
  esac
}

# Figure out the architecture of the current machine.
function GetArchVersion
{
  local version=$( uname -m )

  case "${version}" in
    x86_64)
      ARCH_VERSION=amd64
      return 0
    ;;
    x86-64)
      ARCH_VERSION=amd64
      return 0
    ;;
    *)
      echo "[x] ${version} architecture is not supported. Only x86_64 (i.e. amd64) are supported."
      return 1
    ;;
  esac
}

function DownloadCxxCommon
{
  if ! curl -O "https://s3.amazonaws.com/cxx-common/${LIBRARY_VERSION}.tar.gz"; then
    return 1
  fi

  local TAR_OPTIONS="--warning=no-timestamp"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    TAR_OPTIONS=""
  fi

  tar xf "${LIBRARY_VERSION}.tar.gz" $TAR_OPTIONS
  rm "${LIBRARY_VERSION}.tar.gz"

  # Make sure modification times are not in the future.
  find "${BUILD_DIR}/libraries" -type f -exec touch {} \;

  return 0
}

function DownloadZ3
{
  if ! curl -OL "https://github.com/Z3Prover/z3/releases/download/z3-$Z3_VERSION/${Z3_ARCHIVE}.zip"; then
    return 1
  fi

  unzip -qq "${Z3_ARCHIVE}.zip"
  rm "${Z3_ARCHIVE}.zip"
  mv "${Z3_ARCHIVE}" "${BUILD_DIR}/libraries/z3"

  # Make sure modification times are not in the future.
  find "${BUILD_DIR}/libraries" -type f -exec touch {} \;

  return 0
}

# Attempt to detect the OS distribution name.
function GetOSVersion
{
  source /etc/os-release

  case "${ID,,}" in
    *ubuntu*)
      GetUbuntuOSVersion
      return 0
    ;;

    *opensuse*)
      OS_VERSION=opensuse
      return 0
    ;;

    *arch*)
      OS_VERSION=ubuntu1604
      return 0
    ;;

    *)
      echo "[x] ${ID} is not yet a supported distribution."
      return 1
    ;;
  esac
}

# Attempt to determine Z3 version from ARCH_VERSION and OS_VERSION
function GetZ3ArchiveName
{
  if [[ "$ARCH_VERSION" == "amd64" ]]; then
    Z3_ARCH_VERSION="x64"
  else
    echo "[x] Z3 does not support ${ARCH_VERSION}."
    return 1
  fi

  case "${OS_VERSION}" in
    ubuntu1404)
      Z3_OS_VERSION="ubuntu-14.04"
    ;;

    ubuntu1604)
      Z3_OS_VERSION="ubuntu-16.04"
    ;;

    ubuntu1804)
      Z3_OS_VERSION="ubuntu-16.04"
    ;;

    osx)
      Z3_OS_VERSION="osx"
    ;;

    *)
      echo "[x] Z3 does not support ${OS_VERSION}."
      return 1
    ;;
  esac

  Z3_ARCHIVE="z3-$Z3_VERSION-$Z3_ARCH_VERSION-$Z3_OS_VERSION"
}

# Download pre-compiled version of cxx-common for this OS. This has things like
# google protobuf, gflags, glog, gtest, capstone, and llvm in it. Also download
# prebuilt z3 from https://github.com/Z3Prover/z3/releases/.
function DownloadLibraries
{
  # macOS packages
  if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_VERSION=osx

  # Linux packages
  elif [[ "$OSTYPE" == "linux-gnu" ]]; then
    if ! GetOSVersion; then
      return 1
    fi
  else
    echo "[x] OS ${OSTYPE} is not supported."
    return 1
  fi

  if ! GetArchVersion; then
    return 1
  fi

  LIBRARY_VERSION="libraries-${LLVM_VERSION}-${OS_VERSION}-${ARCH_VERSION}"

  if ! GetZ3ArchiveName; then
      return 1
  fi

  echo "[-] Library version is ${LIBRARY_VERSION}"
  echo "[-] Z3 version is ${Z3_ARCHIVE}"

  if [[ ! -d "${BUILD_DIR}/libraries" ]]; then
    if ! DownloadCxxCommon; then
      echo "[x] Unable to download cxx-common build ${LIBRARY_VERSION}."
      return 1
    fi
    if ! DownloadZ3; then
      echo "[x] Unable to download z3 build ${Z3_ARCHIVE}."
      return 1
    fi
  fi

  return 0
}

# Configure the build.
function Configure
{
  # Tell the rellic CMakeLists.txt where the extracted libraries are.
  export TRAILOFBITS_LIBRARIES="${BUILD_DIR}/libraries"
  export PATH="${TRAILOFBITS_LIBRARIES}/cmake/bin:${TRAILOFBITS_LIBRARIES}/llvm/bin:${PATH}"

  if [[ "${USE_HOST_COMPILER}" = "1" ]] ; then
    if [[ "x${CC}x" = "xx" ]] ; then
      export CC=$(which cc)
    fi

    if [[ "x${CXX}x" = "xx" ]] ; then
      export CXX=$(which c++)
    fi
  else
    export CC="${TRAILOFBITS_LIBRARIES}/llvm/bin/clang"
    export CXX="${TRAILOFBITS_LIBRARIES}/llvm/bin/clang++"
  fi

  # Configure the rellic build, specifying that it should use the pre-built
  # Clang compiler binaries.
  "${TRAILOFBITS_LIBRARIES}/cmake/bin/cmake" \
      -DZ3_INSTALL_PREFIX="${TRAILOFBITS_LIBRARIES}/z3" \
      -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
      -DCMAKE_C_COMPILER="${CC}" \
      -DCMAKE_CXX_COMPILER="${CXX}" \
      -DCMAKE_VERBOSE_MAKEFILE=True \
      ${BUILD_FLAGS} \
      "${SRC_DIR}"

  return $?
}

# Compile the code.
function Build
{
  if [[ "$OSTYPE" == "darwin"* ]]; then
    NPROC=$( sysctl -n hw.ncpu )
  else
    NPROC=$( nproc )
  fi
  make -j"${NPROC}"
  return $?
}

# Get a LLVM version name for the build. This is used to find the version of
# cxx-common to download.
function GetLLVMVersion
{
  case ${1} in
    3.5)
      LLVM_VERSION=llvm35
      USE_HOST_COMPILER=1
      return 0
    ;;
    3.6)
      LLVM_VERSION=llvm36
      USE_HOST_COMPILER=1
      return 0
    ;;
    3.7)
      LLVM_VERSION=llvm37
      USE_HOST_COMPILER=1
      return 0
    ;;
    3.8)
      LLVM_VERSION=llvm38
      USE_HOST_COMPILER=1
      return 0
    ;;
    3.9)
      LLVM_VERSION=llvm39
      USE_HOST_COMPILER=1
      return 0
    ;;
    4.0)
      LLVM_VERSION=llvm40
      USE_HOST_COMPILER=1
      return 0
    ;;
    5.0)
      LLVM_VERSION=llvm50
      return 0
    ;;
    6.0)
      LLVM_VERSION=llvm60
      return 0
    ;;
    7.0)
      LLVM_VERSION=llvm70
      return 0
    ;;
    8.0)
      LLVM_VERSION=llvm80
      return 0
    ;;
    *)
      # unknown option
      echo "[x] Unknown LLVM version ${1}."
    ;;
  esac
  return 1
}

function main
{
  while [[ $# -gt 0 ]] ; do
    key="$1"

    case $key in

      # Change the default installation prefix.
      --prefix)
        INSTALL_DIR=$(python -c "import os; import sys; sys.stdout.write(os.path.abspath('${2}'))")
        echo "[+] New install directory is ${INSTALL_DIR}"
        shift # past argument
      ;;

      # Change the default LLVM version.
      --llvm-version)
        if ! GetLLVMVersion "${2}" ; then
          return 1
        fi
        echo "[+] New LLVM version is ${LLVM_VERSION}"
        shift
      ;;

      # Change the default build directory.
      --build-dir)
        BUILD_DIR=$(python -c "import os; import sys; sys.stdout.write(os.path.abspath('${2}'))")
        echo "[+] New build directory is ${BUILD_DIR}"
        shift # past argument
      ;;

      # Make the build type to be a debug build.
      --debug)
        BUILD_FLAGS="${BUILD_FLAGS} -DCMAKE_BUILD_TYPE=Debug"
        echo "[+] Enabling a debug build of rellic"
      ;;

      --extra-cmake-args)
        BUILD_FLAGS="${BUILD_FLAGS} ${2}"
        echo "[+] Will supply additional arguments to cmake: ${BUILD_FLAGS}"
        shift
      ;;

      --use-host-compiler)
        USE_HOST_COMPILER=1
        echo "[+] Forcing use of host compiler for build"
      ;;

      *)
        # unknown option
        echo "[x] Unknown option: ${key}"
        return 1
      ;;
    esac

    shift # past argument or value
  done

  mkdir -p "${BUILD_DIR}"
  cd "${BUILD_DIR}" || exit 1

  if ! (DownloadLibraries && Configure && Build); then
    echo "[x] Build aborted."
  fi

  return $?
}

main "$@"
exit $?
