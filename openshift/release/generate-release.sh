#!/usr/bin/env bash

set -euo pipefail

source $(dirname $0)/resolve.sh

GITHUB_ACTIONS=true $(dirname $0)/../../hack/update-codegen.sh
git apply openshift/patches/refactor_newfilters.patch
git apply openshift/patches/rekt-serviceaccounts-delete.patch

# Eventing core will bring the config tracing ConfigMap, so remove it from heret
rm -f control-plane/config/eventing-kafka-broker/200-controller/100-config-tracing.yaml

release=$(yq r openshift/project.yaml project.tag)
tag=$release
release=${release/knative-/}

echo "Release: $release"

./openshift/generate.sh

artifacts_dir="openshift/release/artifacts/"
rm -rf $artifacts_dir
mkdir -p $artifacts_dir

image_prefix="registry.ci.openshift.org/openshift/knative-eventing-kafka-broker"

eventing_kafka_controller="${artifacts_dir}eventing-kafka-controller.yaml"
eventing_kafka_post_install="${artifacts_dir}eventing-kafka-post-install.yaml"

eventing_kafka_source="${artifacts_dir}eventing-kafka-source.yaml"
eventing_kafka_broker="${artifacts_dir}eventing-kafka-broker.yaml"
eventing_kafka_channel="${artifacts_dir}eventing-kafka-channel.yaml"
eventing_kafka_sink="${artifacts_dir}eventing-kafka-sink.yaml"

eventing_kafka_tls_networking="${artifacts_dir}eventing-kafka-tls-networking.yaml"

eventing_kafka="${artifacts_dir}eventing-kafka.yaml"

# the Broker Control Plane parts
resolve_resources control-plane/config/eventing-kafka-broker/100-broker $eventing_kafka_controller "$image_prefix" "$tag"
resolve_resources control-plane/config/eventing-kafka-broker/100-sink $eventing_kafka_controller "$image_prefix" "$tag"
resolve_resources control-plane/config/eventing-kafka-broker/100-source $eventing_kafka_controller "$image_prefix" "$tag"
resolve_resources control-plane/config/eventing-kafka-broker/100-channel $eventing_kafka_controller "$image_prefix" "$tag"
resolve_resources control-plane/config/eventing-kafka-broker/100-kafka-internal $eventing_kafka_controller "$image_prefix" "$tag"
resolve_resources control-plane/config/eventing-kafka-broker/200-controller $eventing_kafka_controller "$image_prefix" "$tag"
resolve_resources control-plane/config/eventing-kafka-broker/200-webhook $eventing_kafka_controller "$image_prefix" "$tag"

# the Broker Data Plane folders
resolve_resources data-plane/config/broker $eventing_kafka_broker "$image_prefix" "$tag"
resolve_resources data-plane/config/sink $eventing_kafka_sink "$image_prefix" "$tag"
resolve_resources data-plane/config/source $eventing_kafka_source "$image_prefix" "$tag"
resolve_resources data-plane/config/channel $eventing_kafka_channel "$image_prefix" "$tag"

# TLS resources
resolve_resources data-plane/config/broker-tls $eventing_kafka_tls_networking "$image_prefix" "$tag"
resolve_resources data-plane/config/channel-tls $eventing_kafka_tls_networking "$image_prefix" "$tag"
resolve_resources data-plane/config/sink-tls $eventing_kafka_tls_networking "$image_prefix" "$tag"

# Post-install jobs
resolve_resources control-plane/config/post-install $eventing_kafka_post_install "$image_prefix" "$tag"

# One file with everything
cat $eventing_kafka_controller >> $eventing_kafka
cat $eventing_kafka_post_install >> $eventing_kafka
cat $eventing_kafka_source >> $eventing_kafka
cat $eventing_kafka_broker >> $eventing_kafka
cat $eventing_kafka_channel >> $eventing_kafka
cat $eventing_kafka_sink >> $eventing_kafka
