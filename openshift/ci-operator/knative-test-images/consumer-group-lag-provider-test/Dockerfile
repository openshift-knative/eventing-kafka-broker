# DO NOT EDIT! Generated Dockerfile for test/test_images/consumer-group-lag-provider-test.
ARG GO_BUILDER=registry.ci.openshift.org/openshift/release:rhel-9-release-golang-1.24-openshift-4.20
ARG GO_RUNTIME=registry.access.redhat.com/ubi9/ubi-minimal

FROM $GO_BUILDER as builder

WORKDIR /workspace
COPY . .

ENV CGO_ENABLED=1
ENV GOEXPERIMENT=strictfipsruntime

RUN go build -tags strictfipsruntime -o /usr/bin/main ./test/test_images/consumer-group-lag-provider-test

FROM $GO_RUNTIME

ARG VERSION=knative-v1.21

COPY --from=builder /usr/bin/main /usr/bin/consumer-group-lag-provider-test
COPY LICENSE /licenses/

USER 65532

LABEL \
      com.redhat.component="openshift-serverless-1-eventing-kafka-broker-test-test-images-consumer-group-lag-provider-test-rhel9-container" \
      name="openshift-serverless-1/eventing-kafka-broker-test-test-images-consumer-group-lag-provider-test-rhel9" \
      version=$VERSION \
      summary="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Test Test Images Consumer Group Lag Provider Test" \
      maintainer="serverless-support@redhat.com" \
      description="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Test Test Images Consumer Group Lag Provider Test" \
      io.k8s.display-name="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Test Test Images Consumer Group Lag Provider Test" \
      io.k8s.description="Red Hat OpenShift Serverless Eventing Kafka Broker Test Test Images Consumer Group Lag Provider Test" \
      io.openshift.tags="test-test-images-consumer-group-lag-provider-test" \
      vendor="Red Hat, Inc." \
      release=$VERSION \
      cpe="cpe:/a:redhat:openshift_serverless:1.41::el9"

ENTRYPOINT ["/usr/bin/consumer-group-lag-provider-test"]
