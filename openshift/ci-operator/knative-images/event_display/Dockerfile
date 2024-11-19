# DO NOT EDIT! Generated Dockerfile for vendor/knative.dev/eventing/cmd/event_display.
ARG GO_BUILDER=registry.ci.openshift.org/openshift/release:rhel-8-release-golang-1.22-openshift-4.17
ARG GO_RUNTIME=registry.access.redhat.com/ubi8/ubi-minimal

FROM $GO_BUILDER as builder

WORKDIR /workspace
COPY . .

ENV CGO_ENABLED=1
ENV GOEXPERIMENT=strictfipsruntime

RUN go build -tags strictfipsruntime -o /usr/bin/main ./vendor/knative.dev/eventing/cmd/event_display

FROM $GO_RUNTIME

ARG VERSION=knative-v1.16

COPY --from=builder /usr/bin/main /usr/bin/event_display
COPY LICENSE /licenses/

USER 65532

LABEL \
      com.redhat.component="openshift-serverless-1-eventing-kafka-broker-event-display-rhel8-container" \
      name="openshift-serverless-1/eventing-kafka-broker-event-display-rhel8" \
      version=$VERSION \
      summary="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Event Display" \
      maintainer="serverless-support@redhat.com" \
      description="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Event Display" \
      io.k8s.display-name="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Event Display" \
      io.k8s.description="Red Hat OpenShift Serverless Eventing Kafka Broker Event Display" \
      io.openshift.tags="event-display"

ENTRYPOINT ["/usr/bin/event_display"]
