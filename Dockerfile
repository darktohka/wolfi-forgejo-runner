FROM --platform=$BUILDPLATFORM chainguard/wolfi-base AS buildctl

ARG TARGETPLATFORM

RUN \
  cd /tmp && \
  apk add go curl

RUN \
  if [ "$TARGETPLATFORM" = "linux/arm64" ]; then \
  export GOARCH="arm64"; \
  elif [ "$TARGETPLATFORM" = "linux/arm/v7" ]; then \
  export GOARCH="arm"; \
  else \
  export GOARCH="amd64"; \
  fi && \
  cd /tmp && \
  curl -SsL https://github.com/moby/buildkit/archive/refs/heads/master.tar.gz | tar -xz && \
  mv buildkit-* buildkit && \
  cd buildkit && \
  go build -ldflags "-s -w" ./cmd/buildctl

FROM chainguard/wolfi-base AS proot

RUN \
  apk add clang make curl python3 pkgconf git \
  && cd /tmp \
  && apk add python3 pkgconf \
  && curl -SsL https://www.samba.org/ftp/talloc/talloc-2.4.3.tar.gz | tar -xz \
  && cd talloc-* \
  && ./configure build  --disable-rpath --disable-python \
  && mkdir -p /usr/local/lib /usr/local/include /usr/lib/pkgconfig \
  && ar rcs /usr/local/lib/libtalloc.a bin/default/talloc*.o \
  && cp -f talloc.h /usr/local/include \
  && cp bin/default/talloc.pc /usr/lib/pkgconfig/ \
  && cd /tmp \
  && rm -rf talloc-* \
  && git clone https://github.com/darktohka/proot \
  && cd proot \
  && make -C src loader.elf build.h \
  && make -C src proot

FROM --platform=$BUILDPLATFORM chainguard/wolfi-base AS rust

ARG TARGETPLATFORM

ENV PATH="/root/.cargo/bin:/root/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin:/root/.rustup/toolchains/stable-aarch64-unknown-linux-gnu/bin:$PATH"

RUN \
  if [ "$TARGETPLATFORM" = "linux/arm64" ]; then \
  export RUSTTARGET="aarch64-unknown-linux-gnu"; \
  elif [ "$TARGETPLATFORM" = "linux/arm/v7" ]; then \
  export RUSTTARGET="armv7-unknown-linux-gnueabihf"; \
  else \
  export RUSTTARGET="x86_64-unknown-linux-gnu"; \
  fi \
  && apk add bash curl clang rustup \
  && ln -s /usr/bin/clang /usr/bin/aarch64-linux-gnu-gcc \
  && ln -s /usr/bin/ld /usr/bin/aarch64-linux-gnu-ld \
  && cd /tmp \
  && mkdir -p /tmp/binaries \
  && rustup default stable \
  && rustup target add $RUSTTARGET \
  && curl -SsL https://github.com/darktohka/ocitool/archive/refs/heads/master.tar.gz | tar -xz \
  && mv ocitool-* ocitool \
  && cd ocitool \
  && cargo build --profile release-lto --target "$RUSTTARGET" \
  && mv target/$RUSTTARGET/release-lto/ocitool /tmp/binaries/ocitool \
  && cd /tmp \
  && rm -rf ocitool \
  && curl -SsL https://github.com/darktohka/knock-rs/archive/refs/heads/master.tar.gz | tar -xz \
  && mv knock-rs-* knock-rs \
  && cd knock-rs \
  && cargo build --profile release-lto --bin knock --target "$RUSTTARGET" \
  && mv target/$RUSTTARGET/release-lto/knock /tmp/binaries/knock \
  && cd /tmp \
  && rm -rf knock-rs

FROM chainguard/wolfi-base

RUN \
  apk add bash ca-certificates curl git openssh-client procps nodejs-22 jq && \
  NODE_VERSION=$(apk list -I nodejs-22 | cut -d'-' -f3) && \
  NODE_ALT_VERSIONS="20.18.3 18.20.6 16.20.2" && \
  mkdir -p /opt/acttoolcache/node/${NODE_VERSION}/x64/bin && \
  ln -s $(which node) /opt/acttoolcache/node/${NODE_VERSION}/x64/bin/node && \
  for version in $NODE_ALT_VERSIONS; do ln -s /opt/acttoolcache/node/${NODE_VERSION} /opt/acttoolcache/node/${version}; done

COPY --from=buildctl /tmp/buildkit/buildctl /usr/bin/buildctl
COPY --from=proot /tmp/proot/src/proot /usr/bin/proot
COPY --from=rust /tmp/binaries/* /usr/bin/
COPY ./scripts/* /usr/bin/