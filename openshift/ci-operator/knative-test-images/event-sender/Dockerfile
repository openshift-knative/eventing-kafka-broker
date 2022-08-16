# Do not edit! This file was generate via Makefile
FROM registry.ci.openshift.org/openshift/release:golang-1.17 as builder

COPY . .
RUN make install test-install

FROM openshift/origin-base

COPY --from=builder /go/bin/event-sender /usr/bin/event-sender
ENTRYPOINT ["/usr/bin/event-sender"]
