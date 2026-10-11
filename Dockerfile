##= BUILDER =##
# Same toolchain and build sequence as the Linux release binaries in
# .github/workflows/release.yml: fully static (musl + static OpenSSL).
FROM crystallang/crystal:1.21.1-alpine AS builder
WORKDIR /cryload

# src/cryload/version.cr resolves VERSION at compile time by running
# `shards version` against the shard.yml two directories above it, so the
# COPY layout below (shard.yml at the WORKDIR root, sources in src/) must
# be preserved.
COPY shard.yml ./
COPY src/ src/

# cryload has no runtime dependencies, so build directly with crystal
# instead of `shards install && shards build`: shard.yml only declares the
# ameba dev dependency, and installing it would make every image build
# depend on cloning ameba@master from GitHub for nothing. (`--production`
# is not an option because shard.lock is gitignored.)
RUN apk add --no-cache binutils && \
    mkdir -p bin && \
    crystal build src/main.cr -o bin/cryload --release --static --no-debug && \
    strip bin/cryload

##= RUNNER =##
# The binary is fully static, but Alpine (vs scratch) ships the CA bundle
# HTTPS targets need plus a busybox shell for scripting around results in
# CI. Version/revision labels are injected at build time by
# docker/metadata-action, so only the static ones live here.
FROM alpine:3.22

LABEL org.opencontainers.image.title="cryload"
LABEL org.opencontainers.image.description="HTTP load testing for CI/CD — honest latency, CI thresholds, single binary, JSON output"
LABEL org.opencontainers.image.source="https://github.com/sdogruyol/cryload"
LABEL org.opencontainers.image.licenses="MIT"

RUN apk add --no-cache ca-certificates

COPY --from=builder /cryload/bin/cryload /usr/local/bin/cryload

USER nobody

# ENTRYPOINT keeps the CLI ergonomics:
#   docker run --rm ghcr.io/sdogruyol/cryload https://example.com -n 1000 -c 50
ENTRYPOINT ["cryload"]
CMD ["--help"]
