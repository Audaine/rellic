# Choose your LLVM version
ARG LLVM_VERSION=800
ARG ARCH=amd64
ARG DISTRO_BASE=ubuntu18.04
ARG LIBRARIES=/opt/trailofbits/libraries
ARG Z3_VERSION=4.7.1
#this seems to be static for most Z3 Linux builds
ARG Z3_OS_VERSION=ubuntu-16.04
ARG Z3_ARCHIVE=z3-${Z3_VERSION}-x64-${Z3_OS_VERSION}

# Run-time dependencies go here
FROM trailofbits/cxx-common:llvm${LLVM_VERSION}-${DISTRO_BASE}-${ARCH} as base
ARG Z3_ARCHIVE
ARG Z3_VERSION
ARG LIBRARIES
#FROM ubuntu:18.04 as base
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
     libgomp1 unzip curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

#TODO: replace with git clone & build of the version to work on non-amd64 arch
RUN curl -OL "https://github.com/Z3Prover/z3/releases/download/z3-${Z3_VERSION}/${Z3_ARCHIVE}.zip" && \
    unzip -qq "${Z3_ARCHIVE}.zip" && \
    mv "${Z3_ARCHIVE}" "${LIBRARIES}/z3" && \
    rm "${Z3_ARCHIVE}.zip"

# Build-time dependencies go here
FROM base as deps
RUN apt-get update && \
    apt-get install -y \
     git \
     python \
     python3.7 \
     wget \
     curl \
     gcc-multilib \
     g++-multilib \
     build-essential \
     libtinfo-dev \
     lsb-release \
     zlib1g-dev \
     unzip \
     ninja-build \
     libomp-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Source code build
FROM deps as build
ARG LLVM_VERSION
ARG LIBRARIES

ENV TRAILOFBITS_LIBRARIES="${LIBRARIES}"
WORKDIR /rellic-build
COPY ./ ./
# LLVM 7.0 doesn't work without `--use-host-compiler`
RUN ./scripts/build.sh \
  --llvm-version llvm${LLVM_VERSION} \
  --prefix /opt/trailofbits/rellic \
  --use-host-compiler \
  --extra-cmake-args "-DCMAKE_BUILD_TYPE=Release" \
  --build-only
RUN cd rellic-build && \
    "${LIBRARIES}/cmake/bin/cmake" --build . --verbose --target test && \
    "${LIBRARIES}/cmake/bin/cmake" --build . --target install


# Small installation image
FROM base as install
ARG LLVM_VERSION
ARG LIBRARIES
ENV TRAILOFBITS_LIBRARIES="${LIBRARIES}"

COPY --from=build /opt/trailofbits/rellic /opt/trailofbits/rellic
COPY scripts/docker-decomp-entrypoint.sh /opt/trailofbits/rellic
ENV LLVM_VERSION=$LLVM_VERSION
ENTRYPOINT ["/opt/trailofbits/rellic/docker-decomp-entrypoint.sh"]
