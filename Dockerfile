#======================================================================================================================
# STAGE 0: build Caddy with the deSEC DNS provider module, and certinfo (used by proxy-certs)
#======================================================================================================================

ARG CADDY_BUILDER=caddy:2.11-builder-alpine
ARG BASE_IMAGE=quay.io/bfren/alpine-s6:alpine3.24-6.3.2

FROM --platform=${BUILDPLATFORM} ${CADDY_BUILDER} AS build
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

ARG CADDY_VERSION=2.11.7
ARG CADDY_DESEC_VERSION=1.1.0

RUN \
    # cross-compile for the target platform (GOARM is only used for linux/arm/v7)
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} GOARM=${TARGETVARIANT#v} \
    xcaddy build v${CADDY_VERSION} \
        --with github.com/caddy-dns/desec@v${CADDY_DESEC_VERSION} \
        --output /caddy

# certinfo must come after Caddy, so changing certinfo does not invalidate the cached Caddy build
WORKDIR /src/certinfo
COPY ./certinfo .
RUN \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} GOARM=${TARGETVARIANT#v} \
    go build -trimpath -ldflags="-s -w" -o /certinfo .


#======================================================================================================================
# STAGE 1: create final image
#======================================================================================================================

FROM ${BASE_IMAGE}
COPY --from=build /caddy /usr/bin/caddy
COPY --from=build /certinfo /usr/bin/certinfo

LABEL org.opencontainers.image.description="Caddy reverse proxy with automatic SSL, configured using JSON."
LABEL org.opencontainers.image.source="https://github.com/bfren/docker-caddy-proxy"

ARG BF_IMAGE
ARG BF_PUBLISHING
ARG BF_VERSION

# release of https://github.com/ai-robots-txt/ai.robots.txt used for the list of AI training crawlers to block
ARG AI_ROBOTS_VERSION=v2.0

# 443/udp is used for HTTP/3
EXPOSE 80 443 443/udp

COPY ./overlay /

ENV \
    # the domain of the proxy server - requests for unknown hosts will be redirected here
    BF_PROXY_DOMAIN= \
    # remove all domain configuration and certificates before starting
    BF_PROXY_CLEAN_INSTALL=0 \
    # used for Let's Encrypt registration and expiry notification emails
    BF_PROXY_LETS_ENCRYPT_EMAIL= \
    # set to 1 to use the Let's Encrypt live server instead of staging
    BF_PROXY_LETS_ENCRYPT_LIVE=0 \
    # set to 1 to use Caddy's internal (self-signed) CA instead of Let's Encrypt - for testing / local use
    BF_PROXY_USE_INTERNAL_CA=0 \
    # default ACME challenge for domains: 'http' or 'dns' (can be set per domain in conf.json)
    BF_PROXY_ACME_CHALLENGE=http \
    # optional - time to wait before checking DNS propagation (e.g. 60s), and how long to wait for it (e.g. 5m)
    BF_PROXY_DNS_PROPAGATION_DELAY= \
    BF_PROXY_DNS_PROPAGATION_TIMEOUT= \
    # optional - space-separated DNS resolvers to use when checking propagation (e.g. "1.1.1.1 9.9.9.9")
    BF_PROXY_DNS_RESOLVERS= \
    # set to 1 to allow only TLS 1.3
    BF_PROXY_HARDEN=0 \
    # set to 1 to redirect aliases to the primary domain by default (can be set per domain in conf.json)
    BF_PROXY_SSL_REDIRECT_TO_CANONICAL=0 \
    # set to 1 to block AI crawlers that collect training data (see ai.robots.txt)
    BF_PROXY_BLOCK_AI_BOTS=1 \
    # set to 1 to enable access logs
    BF_PROXY_ACCESS_LOG=0 \
    # if conf.json does not exist and both are set, it will be generated on startup
    BF_PROXY_AUTO_PRIMARY= \
    BF_PROXY_AUTO_UPSTREAM= \
    # optional - space-separated aliases to add to the auto-generated conf.json
    BF_PROXY_AUTO_ALIASES= \
    # optional - mark the auto-generated domain as custom
    BF_PROXY_AUTO_CUSTOM=0 \
    # the number of seconds before the maintenance page will auto-refresh
    BF_PROXY_MAINTENANCE_REFRESH_SECONDS=6

RUN bf-install

VOLUME [ "/ssl", "/sites", "/www" ]
