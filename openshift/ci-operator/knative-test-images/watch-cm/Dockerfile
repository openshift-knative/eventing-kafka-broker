# DO NOT EDIT! Generated Dockerfile for test/cmd/watch-cm.
ARG GO_BUILDER=registry.ci.openshift.org/openshift/release:rhel-9-release-golang-1.23-openshift-4.19
ARG GO_RUNTIME=registry.access.redhat.com/ubi9/ubi-minimal

FROM $GO_BUILDER as builder

WORKDIR /workspace
COPY . .

ENV CGO_ENABLED=1
ENV GOEXPERIMENT=strictfipsruntime

RUN go build -tags strictfipsruntime -o /usr/bin/main ./test/cmd/watch-cm

FROM $GO_RUNTIME

ARG VERSION=knative-v1.18

COPY --from=builder /usr/bin/main /usr/bin/watch-cm
COPY LICENSE /licenses/

USER 65532

LABEL \
      com.redhat.component="openshift-serverless-1-eventing-kafka-broker-watch-cm-rhel9-container" \
      name="openshift-serverless-1/eventing-kafka-broker-watch-cm-rhel9" \
      version=$VERSION \
      summary="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Watch Cm" \
      maintainer="serverless-support@redhat.com" \
      description="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Watch Cm" \
      io.k8s.display-name="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Watch Cm" \
      io.k8s.description="Red Hat OpenShift Serverless Eventing Kafka Broker Watch Cm" \
      io.openshift.tags="watch-cm" \
      vendor="Red Hat, Inc." \
      release=$VERSION \
      cpe="cpe:/a:redhat:openshift_serverless:1.38::el9"

ENTRYPOINT ["/usr/bin/watch-cm"]
