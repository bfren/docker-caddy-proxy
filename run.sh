#!/bin/sh

IMAGE=caddy-proxy
VERSION=`cat VERSION`
TAG=${IMAGE}-dev

docker buildx build \
    --load \
    --build-arg BF_IMAGE=${IMAGE} \
    --build-arg BF_VERSION=${VERSION} \
    -t ${TAG} \
    . \
    && \
    docker run -it \
        -e BF_DEBUG=1 \
        -e BF_PROXY_DOMAIN=localhost \
        -e BF_PROXY_USE_INTERNAL_CA=1 \
        -p 127.0.0.1:8080:80 \
        -p 127.0.0.1:8443:443 \
        ${TAG} \
        sh
