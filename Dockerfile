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

FROM chainguard/wolfi-base AS ocitool

RUN \
  apk add rust curl clang \
  && cd /tmp \
  && curl -SsL https://github.com/darktohka/ocitool/archive/refs/heads/master.tar.gz | tar -xz \
  && mv ocitool-* ocitool \
  && cd ocitool \
  && cargo build --release

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
COPY --from=ocitool /tmp/ocitool/target/release/ocitool /usr/bin/ocitool
COPY ./scripts/* /usr/bin/