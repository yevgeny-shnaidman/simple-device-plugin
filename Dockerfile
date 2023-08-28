ARG BASE_IMAGE='scratch'

FROM ${BASE_IMAGE}
COPY simple-device-plugin /simple-device-plugin
ENTRYPOINT ["/simple-device-plugin"]
