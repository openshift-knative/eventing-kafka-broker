# Do not edit! This file was generate via Makefile
FROM registry.ci.openshift.org/openshift/release:golang-1.19 as builder

COPY . .
RUN make install test-install

FROM registry.access.redhat.com/ubi8/ubi-minimal
USER 65532

COPY --from=builder /go/bin/wathola-sender /usr/bin/wathola-sender
ENTRYPOINT ["/usr/bin/wathola-sender"]
