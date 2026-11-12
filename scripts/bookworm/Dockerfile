# vim: filetype=dockerfile
#
# CPU-only ollama payload built FOR Debian 12 bookworm (glibc 2.36).
#
# Reuses the repo's own `cpu` CMake preset (llama/server, GGML_CPU_ALL_VARIANTS,
# GGML_OPENMP=OFF) and the same Go build line as the Dockerfile's
# build-cpu-only stage, but pins the toolchain to bookworm's GCC 12 so the
# result never references a GLIBC newer than 2.36 (GCC 13 emits GLIBCXX_3.4.32,
# which bookworm's libstdc++ 3.4.31 cannot satisfy).
#
# Run from the repo root:
#   docker build --platform linux/amd64 -f scripts/bookworm/Dockerfile \
#       --target payload -t ollama-cpu-bookworm:payload .
# then `docker run --rm ollama-cpu-bookworm:payload` prints the verify report,
# and `docker cp` / a scratch stage exports /out.

ARG GO_GIT_TAG

FROM --platform=linux/amd64 debian:12-slim AS base
ARG DEBIAN_FRONTEND=noninteractive
ENV CMAKE_GENERATOR=Ninja \
    LDFLAGS=-s
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git unzip xz-utils \
        gcc-12 g++-12 build-essential cmake ninja-build \
        binutils file patch \
    && rm -rf /var/lib/apt/lists/*
# Force GCC 12 everywhere (bookworm default is already 12, this makes it explicit
# and survives a future default change).
RUN update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-12 100 \
    && update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-12 100 \
    && gcc --version && cmake --version && ninja --version

# ---------------------------------------------------------------------------
# Go toolchain: not in bookworm, so fetch the upstream tarball for the repo's
# go.mod version. The Go binary itself only runs at build time.
# ---------------------------------------------------------------------------
FROM base AS gotool
WORKDIR /src
COPY go.mod go.sum ./
RUN curl --retry 3 -fsSL "https://go.dev/dl/go$(awk '/^go/ { print $2 }' go.mod).linux-amd64.tar.gz" -o /tmp/go.tar.gz \
    && tar xzf /tmp/go.tar.gz -C /usr/local \
    && rm /tmp/go.tar.gz
ENV PATH=/usr/local/go/bin:/root/go/bin:$PATH
RUN go version

# ---------------------------------------------------------------------------
# llama-server + ggml CPU variants  ->  /out/lib/ollama
# ---------------------------------------------------------------------------
FROM gotool AS llama-server-cpu
COPY LLAMA_CPP_VERSION ./
COPY llama/server llama/server
COPY llama/compat llama/compat
COPY cmake cmake
RUN --mount=type=cache,target=/root/.ccache \
    cmake -S llama/server --preset cpu \
    && cmake --build build/llama-server-cpu -- -l $(nproc) \
    && cmake --install build/llama-server-cpu --component llama-server --strip

FROM scratch AS llama-server-payload
COPY --from=llama-server-cpu /src/dist/lib/ollama /out/lib/ollama/

# ---------------------------------------------------------------------------
# Go CLI (cgo, PIE) + Go license  ->  /out/bin/ollama
# ---------------------------------------------------------------------------
FROM gotool AS go-build
ARG GO_GIT_TAG
COPY . .
ENV CGO_ENABLED=1
ENV GOAMD64=v1
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/root/go/pkg/mod \
    go build -trimpath -gcflags=all=-l \
        -ldflags="-s -w -buildid= -X github.com/ollama/ollama/version.Version=${GO_GIT_TAG}" \
        -o /out/bin/ollama .
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/root/go/pkg/mod \
    cmake -S . -B build/go-license -DOLLAMA_LLAMA_BACKENDS= -DOLLAMA_MLX_BACKENDS= \
    && cmake --build build/go-license --target ollama-go-license \
    && mkdir -p /out/lib/ollama \
    && cp build/go-license/lib/ollama/GO_LICENSE /out/lib/ollama/GO_LICENSE

FROM scratch AS go-payload
COPY --from=go-build /out /out

# ---------------------------------------------------------------------------
# Verification (runs on bookworm itself: glibc 2.36, libstdc++ 3.4.31)
# ---------------------------------------------------------------------------
FROM --platform=linux/amd64 debian:12-slim AS verify
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl binutils libgomp1 binutils \
    && rm -rf /var/lib/apt/lists/*
COPY --from=llama-server-cpu /src/dist/lib/ollama /opt/ollama/lib/ollama
COPY --from=go-build /out/bin/ollama /opt/ollama/bin/ollama
COPY --from=go-build /out/lib/ollama/GO_LICENSE /opt/ollama/lib/ollama/GO_LICENSE
COPY scripts/bookworm/verify.sh /usr/local/bin/verify.sh
RUN chmod +x /usr/local/bin/verify.sh
WORKDIR /opt/ollama
ENTRYPOINT ["/usr/local/bin/verify.sh"]

# ---------------------------------------------------------------------------
# export: same tree, but on a base image that HAS bash/binutils, so it can be
# exported to the host with `docker cp` from a trivial container.
# ---------------------------------------------------------------------------
FROM --platform=linux/amd64 debian:12-slim AS export
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates binutils file \
    && rm -rf /var/lib/apt/lists/*
COPY --from=verify /opt/ollama /opt/ollama
COPY scripts/bookworm/measure.sh scripts/bookworm/assemble.sh scripts/bookworm/verify.sh /usr/local/bin/
WORKDIR /opt/ollama
CMD ["/bin/bash"]
