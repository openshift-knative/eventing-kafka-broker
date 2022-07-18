# Do not edit! This file was generate via Makefile
FROM registry.ci.openshift.org/openshift/release:golang-1.17 as builder

COPY . .
RUN make install test-install

FROM openshift/origin-base

COPY --from=builder /go/bin/performance /usr/bin/performance
ENTRYPOINT ["/usr/bin/performance"]
