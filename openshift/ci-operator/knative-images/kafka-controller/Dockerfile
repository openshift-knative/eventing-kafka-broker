# DO NOT EDIT! Generated Dockerfile for control-plane/cmd/kafka-controller.
ARG GO_BUILDER=registry.ci.openshift.org/openshift/release:rhel-8-release-golang-1.23-openshift-4.19
ARG GO_RUNTIME=registry.access.redhat.com/ubi8/ubi-minimal

FROM $GO_BUILDER as builder

WORKDIR /workspace
COPY . .

ENV CGO_ENABLED=1
ENV GOEXPERIMENT=strictfipsruntime

RUN go build -tags strictfipsruntime -o /usr/bin/main ./control-plane/cmd/kafka-controller

FROM $GO_RUNTIME

ARG VERSION=knative-v1.16

COPY --from=builder /usr/bin/main /usr/bin/kafka-controller
COPY LICENSE /licenses/

USER 65532

LABEL \
      com.redhat.component="openshift-serverless-1-eventing-kafka-broker-kafka-controller-rhel8-container" \
      name="openshift-serverless-1/eventing-kafka-broker-kafka-controller-rhel8" \
      version=$VERSION \
      summary="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Kafka Controller" \
      maintainer="serverless-support@redhat.com" \
      description="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Kafka Controller" \
      io.k8s.display-name="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Kafka Controller" \
      io.k8s.description="Red Hat OpenShift Serverless Eventing Kafka Broker Kafka Controller" \
      io.openshift.tags="kafka-controller" \
      cpe="cpe:/a:redhat:openshift_serverless:1.36::el8"

ENTRYPOINT ["/usr/bin/kafka-controller"]
