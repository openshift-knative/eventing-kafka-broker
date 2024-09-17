# DO NOT EDIT! Generated Dockerfile for control-plane/cmd/webhook-kafka.
ARG GO_BUILDER=registry.ci.openshift.org/openshift/release:rhel-8-release-golang-1.22-openshift-4.17
ARG GO_RUNTIME=registry.access.redhat.com/ubi8/ubi-minimal

FROM $GO_BUILDER as builder

COPY . .

ENV CGO_ENABLED=1
ENV GOEXPERIMENT=strictfipsruntime

RUN go build -tags strictfipsruntime -o /usr/bin/main ./control-plane/cmd/webhook-kafka

FROM $GO_RUNTIME

ARG VERSION=knative-nightly

COPY --from=builder /usr/bin/main /usr/bin/webhook-kafka

USER 65532

LABEL \
      com.redhat.component="openshift-serverless-1-eventing-kafka-broker-webhook-kafka-rhel8-container" \
      name="openshift-serverless-1/eventing-kafka-broker-webhook-kafka-rhel8" \
      version=$VERSION \
      summary="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Webhook Kafka" \
      maintainer="serverless-support@redhat.com" \
      description="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Webhook Kafka" \
      io.k8s.display-name="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Webhook Kafka"

ENTRYPOINT ["/usr/bin/webhook-kafka"]
