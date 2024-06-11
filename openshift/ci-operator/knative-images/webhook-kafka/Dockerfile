# DO NOT EDIT! Generated Dockerfile for control-plane/cmd/webhook-kafka.
FROM registry.ci.openshift.org/openshift/release:rhel-8-release-golang-1.21-openshift-4.16 as builder

COPY . .

RUN mkdir -p /var/run/ko && \
    mkdir -p control-plane/cmd/webhook-kafka/kodata && \
    go build -o /usr/bin/main ./control-plane/cmd/webhook-kafka && \
    cp -r control-plane/cmd/webhook-kafka/kodata /var/run/ko

FROM registry.access.redhat.com/ubi8/ubi-minimal

# install the missing zoneinfo to ubi-minimal
RUN microdnf install tzdata

USER 65532

COPY --from=builder /usr/bin/main /usr/bin/main
COPY --from=builder /var/run/ko /var/run/ko
ENTRYPOINT ["/usr/bin/main"]
