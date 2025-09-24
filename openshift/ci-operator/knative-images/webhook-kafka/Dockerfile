# DO NOT EDIT! Generated Dockerfile for control-plane/cmd/webhook-kafka.
ARG GO_BUILDER=registry.ci.openshift.org/openshift/release:rhel-8-release-golang-1.22-openshift-4.17
ARG GO_RUNTIME=registry.access.redhat.com/ubi8/ubi-minimal

FROM $GO_BUILDER as builder

WORKDIR /workspace
COPY . .

ENV CGO_ENABLED=1
ENV GOEXPERIMENT=strictfipsruntime

RUN go build -tags strictfipsruntime -o /usr/bin/main ./control-plane/cmd/webhook-kafka

FROM $GO_RUNTIME

ARG VERSION=knative-v1.15

COPY --from=builder /usr/bin/main /usr/bin/webhook-kafka
COPY LICENSE /licenses/

USER 65532

LABEL \
      com.redhat.component="openshift-serverless-1-eventing-kafka-broker-webhook-kafka-rhel8-container" \
      name="openshift-serverless-1/kn-ekb-webhook-kafka-rhel8" \
      version=$VERSION \
      cpe="cpe:/a:redhat:openshift_serverless:1.35::el8" \
      summary="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Webhook Kafka" \
      maintainer="serverless-support@redhat.com" \
      description="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Webhook Kafka" \
      io.k8s.display-name="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Webhook Kafka" \
      io.k8s.description="Red Hat OpenShift Serverless Eventing Kafka Broker Webhook Kafka" \
      io.openshift.tags="webhook-kafka"

ENTRYPOINT ["/usr/bin/webhook-kafka"]
