# DO NOT EDIT! Generated Dockerfile for vendor/knative.dev/eventing/test/test_images/request-sender.
FROM registry.ci.openshift.org/openshift/release:rhel-8-release-golang-1.22-openshift-4.17 as builder

COPY . .

RUN mkdir -p /var/run/ko && \
    mkdir -p vendor/knative.dev/eventing/test/test_images/request-sender/kodata && \
    go build -o /usr/bin/main ./vendor/knative.dev/eventing/test/test_images/request-sender && \
    cp -r vendor/knative.dev/eventing/test/test_images/request-sender/kodata /var/run/ko

FROM registry.access.redhat.com/ubi8/ubi-minimal

# install the missing zoneinfo to ubi-minimal
RUN microdnf install tzdata

USER 65532

COPY --from=builder /usr/bin/main /usr/bin/main
COPY --from=builder /var/run/ko /var/run/ko
ENTRYPOINT ["/usr/bin/main"]
