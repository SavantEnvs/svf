# syntax=docker/dockerfile:1.7
FROM ghcr.io/savantenvs/base:20260621

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG MAYHEM_JOBS=

USER root
RUN [ -n "$SOURCE_DATE_EPOCH" ] && repro-sources-list.sh || true ; \
    apt-get update && apt-get install -yq --no-install-recommends \
      libncurses-dev libtinfo-dev zlib1g-dev libxml2-dev libzstd-dev \
      unzip xz-utils patchelf \
    && rm -rf /var/lib/apt/lists/*

# Prebuilt LLVM 21.1.0 (RTTI) + Z3 4.8.8, the same artifacts upstream's build.sh
# downloads, pinned by sha256 and installed outside the source tree so the
# offline / git-clean'd re-build of mayhem/build.sh still finds them.
ARG SVF_LLVM_URL=https://github.com/bjjwwang/SVF-LLVM/releases/download/21.1.0/llvm-21.1.0-ubuntu22-rtti-x86-64.tar.gz
ARG SVF_LLVM_SHA256=3fc791d06760fd325f0ba9f2cb45ec5a1b2df1652a06a577751935edabd809f3
ARG SVF_Z3_URL=https://github.com/Z3Prover/z3/releases/download/z3-4.8.8/z3-4.8.8-x64-ubuntu-16.04.zip
ARG SVF_Z3_SHA256=6534f26427ee4f02835d17c3472f5ce750f34b4898c35cdd4223459b3589664e
ENV SVF_DEPS=/opt/toolchains/svf
RUN set -eux; mkdir -p "$SVF_DEPS/llvm"; cd "$SVF_DEPS"; \
    curl -fsSL "$SVF_LLVM_URL" -o llvm.tgz; echo "$SVF_LLVM_SHA256  llvm.tgz" | sha256sum -c -; \
    tar -xf llvm.tgz -C llvm --strip-components 1; rm -f llvm.tgz; \
    curl -fsSL "$SVF_Z3_URL" -o z3.zip; echo "$SVF_Z3_SHA256  z3.zip" | sha256sum -c -; \
    unzip -q z3.zip; mv z3-4.8.8-x64-ubuntu-16.04 z3; rm -f z3.zip
USER mayhem

WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh

ENV LD_LIBRARY_PATH=/opt/toolchains/svf/llvm/lib:/opt/toolchains/svf/z3/bin:/mayhem/Release-build/lib

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
