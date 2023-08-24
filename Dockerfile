ARG BASE_IMAGE='scratch'

FROM registry.access.redhat.com/ubi9/go-toolset:1.19 as builder

ARG TARGETOS='linux'
ARG TARGETARCH

WORKDIR /opt/app-root/src

COPY --chown=1001:0 go.mod go.mod
COPY --chown=1001:0 go.sum go.sum
COPY --chown=1001:0 vendor/ vendor/
COPY --chown=1001:0 main.go main.go
COPY --chown=1001:0 config.go config.go

RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o simple-device-plugin main.go config.go

FROM ${BASE_IMAGE}

WORKDIR /
COPY --from=builder /opt/app-root/src/simple-device-plugin /simple-device-plugin
USER 1001

ENTRYPOINT ["/simple-device-plugin"]
