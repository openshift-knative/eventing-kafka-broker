# DO NOT EDIT! Generated Dockerfile for control-plane/cmd/kafka-controller.
ARG GO_BUILDER=registry.ci.openshift.org/openshift/release:rhel-9-release-golang-1.24-openshift-4.20
ARG GO_RUNTIME=registry.access.redhat.com/ubi9/ubi-minimal

FROM $GO_BUILDER as builder

WORKDIR /workspace
COPY . .

ENV CGO_ENABLED=1
ENV GOEXPERIMENT=strictfipsruntime

RUN go build -tags strictfipsruntime -o /usr/bin/main ./control-plane/cmd/kafka-controller

FROM $GO_RUNTIME

ARG VERSION=knative-v1.20

COPY --from=builder /usr/bin/main /usr/bin/kafka-controller
COPY LICENSE /licenses/

USER 65532

LABEL \
      com.redhat.component="openshift-serverless-1-kn-ekb-kafka-controller-rhel9-container" \
      name="openshift-serverless-1/kn-ekb-kafka-controller-rhel9" \
      version=$VERSION \
      summary="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Kafka Controller" \
      maintainer="serverless-support@redhat.com" \
      description="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Kafka Controller" \
      io.k8s.display-name="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Kafka Controller" \
      io.k8s.description="Red Hat OpenShift Serverless Eventing Kafka Broker Kafka Controller" \
      io.openshift.tags="kafka-controller" \
      vendor="Red Hat, Inc." \
      release=$VERSION \
      cpe="cpe:/a:redhat:openshift_serverless:1.40::el9"

ENTRYPOINT ["/usr/bin/kafka-controller"]
