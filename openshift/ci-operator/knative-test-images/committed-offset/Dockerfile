# DO NOT EDIT! Generated Dockerfile for test/test_images/committed-offset.
ARG GO_BUILDER=registry.ci.openshift.org/openshift/release:rhel-9-release-golang-1.23-openshift-4.19
ARG GO_RUNTIME=registry.access.redhat.com/ubi9/ubi-minimal

FROM $GO_BUILDER as builder

WORKDIR /workspace
COPY . .

ENV CGO_ENABLED=1
ENV GOEXPERIMENT=strictfipsruntime

RUN go build -tags strictfipsruntime -o /usr/bin/main ./test/test_images/committed-offset

FROM $GO_RUNTIME

ARG VERSION=knative-v1.17

COPY --from=builder /usr/bin/main /usr/bin/committed-offset
COPY LICENSE /licenses/

USER 65532

LABEL \
      com.redhat.component="openshift-serverless-1-eventing-kafka-broker-test-test-images-committed-offset-rhel9-container" \
      name="openshift-serverless-1/eventing-kafka-broker-test-test-images-committed-offset-rhel9" \
      version=$VERSION \
      summary="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Test Test Images Committed Offset" \
      maintainer="serverless-support@redhat.com" \
      description="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Test Test Images Committed Offset" \
      io.k8s.display-name="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Test Test Images Committed Offset" \
      io.k8s.description="Red Hat OpenShift Serverless Eventing Kafka Broker Test Test Images Committed Offset" \
      io.openshift.tags="test-test-images-committed-offset" \
      vendor="Red Hat, Inc." \
      release=$VERSION \
      cpe="cpe:/a:redhat:openshift_serverless:1.37::el9"

ENTRYPOINT ["/usr/bin/committed-offset"]
