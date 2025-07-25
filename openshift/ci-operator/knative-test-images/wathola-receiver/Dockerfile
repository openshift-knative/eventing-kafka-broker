# DO NOT EDIT! Generated Dockerfile for vendor/knative.dev/eventing/test/test_images/wathola-receiver.
ARG GO_BUILDER=registry.ci.openshift.org/openshift/release:rhel-9-release-golang-1.24-openshift-4.20
ARG GO_RUNTIME=registry.access.redhat.com/ubi8/ubi-minimal

FROM $GO_BUILDER as builder

WORKDIR /workspace
COPY . .

ENV CGO_ENABLED=1
ENV GOEXPERIMENT=strictfipsruntime

RUN go build -tags strictfipsruntime -o /usr/bin/main ./vendor/knative.dev/eventing/test/test_images/wathola-receiver

FROM $GO_RUNTIME

ARG VERSION=knative-v1.19

COPY --from=builder /usr/bin/main /usr/bin/wathola-receiver
COPY LICENSE /licenses/

USER 65532

LABEL \
      com.redhat.component="openshift-serverless-1-eventing-kafka-broker-vendor-knative.dev-eventing-test-test-images-wathola-receiver-rhel8-container" \
      name="openshift-serverless-1/eventing-kafka-broker-vendor-knative.dev-eventing-test-test-images-wathola-receiver-rhel8" \
      version=$VERSION \
      summary="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Vendor Knative.Dev Eventing Test Test Images Wathola Receiver" \
      maintainer="serverless-support@redhat.com" \
      description="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Vendor Knative.Dev Eventing Test Test Images Wathola Receiver" \
      io.k8s.display-name="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Vendor Knative.Dev Eventing Test Test Images Wathola Receiver" \
      io.k8s.description="Red Hat OpenShift Serverless Eventing Kafka Broker Vendor Knative.Dev Eventing Test Test Images Wathola Receiver" \
      io.openshift.tags="vendor-knative.dev-eventing-test-test-images-wathola-receiver"

ENTRYPOINT ["/usr/bin/wathola-receiver"]
