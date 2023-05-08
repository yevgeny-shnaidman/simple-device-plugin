FROM scratch
COPY simple-device-plugin /simple-device-plugin
ENTRYPOINT ["/simple-device-plugin"]
