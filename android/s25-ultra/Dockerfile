# Reproducible build environment for any OS with Docker (Linux, macOS on
# x86_64, Windows via WSL2). The repo is bind-mounted, not copied, and the
# toolchain cache lives in a named volume so rebuilds are incremental:
#
#   docker build -t mlc-s25 android/s25-ultra
#   docker run --rm -it -v "$PWD":/work -v mlc-s25-home:/root/.mlc-s25 \
#     -w /work mlc-s25 android/s25-ultra/build_all.sh
#
# Then, on the host: android/s25-ultra/60_install_to_phone.sh
# (USB passthrough into containers is unreliable on macOS/Windows).
# Digest pinned Oct 2026; bump deliberately to pick up Ubuntu security updates.
FROM ubuntu:24.04@sha256:68ee22004a9109b44973313b02ff7b1de250f1de0f5ecb628d73f579aaff33ac
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -q && apt-get install -y -q --no-install-recommends \
      sudo git curl ca-certificates && rm -rf /var/lib/apt/lists/*
COPY env.sh 00_bootstrap_ubuntu.sh /opt/s25/
RUN bash /opt/s25/00_bootstrap_ubuntu.sh && rm -rf /var/lib/apt/lists/*
RUN git config --global --add safe.directory '*'
WORKDIR /work
