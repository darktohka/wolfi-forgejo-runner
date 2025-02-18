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

FROM chainguard/wolfi-base

RUN \
  apk add bash ca-certificates curl git openssh-client procps nodejs-22 jq && \
  NODE_VERSION=$(apk list -I nodejs-22 | cut -d'-' -f3) && \
  NODE_ALT_VERSIONS="20.18.3 18.20.6 16.20.2" && \
  mkdir -p /opt/acttoolcache/node/${NODE_VERSION}/x64/bin && \
  ln -s $(which node) /opt/acttoolcache/node/${NODE_VERSION}/x64/bin/node && \
  for version in $NODE_ALT_VERSIONS; do ln -s /opt/acttoolcache/node/${NODE_VERSION} /opt/acttoolcache/node/${version}; done

COPY --from=buildctl /tmp/buildkit/buildctl /usr/bin/buildctl
COPY ./scripts/* /usr/bin/
