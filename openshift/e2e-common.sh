#!/usr/bin/env bash

export EVENTING_NAMESPACE="${EVENTING_NAMESPACE:-knative-eventing}"
export SYSTEM_NAMESPACE=$EVENTING_NAMESPACE
export TRACING_NAMESPACE=$EVENTING_NAMESPACE
export KNATIVE_DEFAULT_NAMESPACE=$EVENTING_NAMESPACE

default_test_image_template=$(
  cat <<-END
{{- with .Name }}
{{- if eq . "event-sender"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_EVENT_SENDER{{end -}}
{{- if eq . "heartbeats"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_HEARTBEATS{{end -}}
{{- if eq . "eventshub"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_EVENTSHUB{{end -}}
{{- if eq . "recordevents"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_RECORDEVENTS{{end -}}
{{- if eq . "print"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_PRINT{{end -}}
{{- if eq . "performance"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_PERFORMANCE{{end -}}
{{- if eq . "committed-offset"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_COMMITTED_OFFSET{{end -}}
{{- if eq . "consumer-group-lag-provider-test"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_CONSUMER_GROUP_LAG_PROVIDER_TEST{{end -}}
{{- if eq . "kafka-consumer"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_KAFKA_CONSUMER{{end -}}
{{- if eq . "partitions-replication-verifier"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_PARTITIONS_REPLICATION_VERIFIER{{end -}}
{{- if eq . "request-sender"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_REQUEST_SENDER{{end -}}
{{end -}}
END
)

export TEST_IMAGE_TEMPLATE=${TEST_IMAGE_TEMPLATE:-$default_test_image_template}

# shellcheck disable=SC1090
source "$(dirname "$0")/../test/e2e-common.sh"

# Loops until duration (car) is exceeded or command (cdr) returns non-zero
function timeout() {
  SECONDS=0
  TIMEOUT=$1
  shift
  while eval $*; do
    sleep 5
    [[ $SECONDS -gt $TIMEOUT ]] && echo "ERROR: Timed out" && return 1
  done
  return 0
}

function scale_up_workers {
  local current_total az_total replicas idx ignored_zone
  local SCALE_UP="$1"
  if [[ "${SCALE_UP}" -lt "0" ]]; then
    logger.info 'Skipping scaling up, because SCALE_UP is negative.'
    return 0
  fi

  if ! cluster_scalable; then
    logger.info 'Skipping scaling up, the cluster is not scalable.'
    return 0
  fi

  logger.info "Scaling cluster to ${SCALE_UP}"

  logger.debug 'Get the machineset with most replicas'
  current_total="$(oc get machineconfigpool worker -o jsonpath='{.status.readyMachineCount}')"

  # WORKAROUND: OpenShift in CI cannot scale machine set in us-east-1e zone and throws:
  # Your requested instance type (m5.xlarge) is not supported in your requested Availability Zone
  # (us-east-1e). Please retry your request by not specifying an Availability Zone
  # or choosing us-east-1a, us-east-1b, us-east-1c, us-east-1d, us-east-1f."
  ignored_zone="us-east-1e"
  az_total="$(oc get machineset -n openshift-machine-api -oname | grep -cv "$ignored_zone")"

  logger.debug "ready machine count: ${current_total}, number of available zones: ${az_total}"

  if [[ "${SCALE_UP}" == "${current_total}" ]]; then
    logger.success "Cluster is already scaled up to ${SCALE_UP} replicas"
    return 0
  fi

  idx=0
  for mset in $(oc get machineset -n openshift-machine-api -o name | grep -v "$ignored_zone"); do
    replicas=$(( SCALE_UP / az_total ))
    if [ ${idx} -lt $(( SCALE_UP % az_total )) ];then
      (( replicas++ )) || true
    fi
    (( idx++ )) || true
    logger.debug "Bump ${mset} to ${replicas}"
    oc scale "${mset}" -n openshift-machine-api --replicas="${replicas}"
  done
  wait_until_machineset_scales_up "${SCALE_UP}"
}

# Waits until worker nodes scale up to the desired number of replicas
# Parameters: $1 - desired number of replicas
function wait_until_machineset_scales_up {
  logger.info "Waiting until worker nodes scale up to $1 replicas"
  local available
  for _ in {1..150}; do  # timeout after 15 minutes
    available=$(oc get machineconfigpool worker -o jsonpath='{.status.readyMachineCount}')
    if [[ ${available} -eq $1 ]]; then
      echo ''
      logger.success "successfully scaled up to $1 replicas"
      return 0
    fi
    echo -n "."
    sleep 6
  done
  echo -e "\n\n"
  logger.error "Timeout waiting for scale up to $1 replicas"
  return 1
}

function cluster_scalable {
  if [[ $(oc get infrastructure cluster -ojsonpath='{.status.platform}') = VSphere ]]; then
    return 1
  fi
}

function install_serverless() {
  header "Installing Serverless Operator"

  cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: knative-eventing
EOF

  ./test/kafka/kafka_setup.sh || return $?
  create_sasl_secrets || return $?
  create_tls_secrets || return $?

  KNATIVE_EVENTING_KAFKA_BROKER_MANIFESTS_DIR="$(pwd)/openshift/release/artifacts"
  export KNATIVE_EVENTING_KAFKA_BROKER_MANIFESTS_DIR

  local operator_dir=/tmp/serverless-operator
  git clone --branch release-1.31 https://github.com/openshift-knative/serverless-operator.git $operator_dir
  export GOPATH=/tmp/go
  local failed=0
  pushd $operator_dir || return $?
  export ON_CLUSTER_BUILDS=true
  export DOCKER_REPO_OVERRIDE=image-registry.openshift-image-registry.svc:5000/openshift-marketplace
  make OPENSHIFT_CI="true" TRACING_BACKEND=zipkin \
    generated-files images install-tracing install-kafka || failed=$?
  popd || return $?

  oc apply -f openshift/knative-eventing.yaml
  oc wait --for=condition=Ready knativeeventing.operator.knative.dev knative-eventing -n knative-eventing --timeout=900s

  return $failed
}

function run_e2e_tests() {

  export BROKER_CLASS="Kafka"

  echo "Running e2e tests, directory ./test/e2e/"
  go_test_e2e -timeout=100m -short ./test/e2e/ \
    -imagetemplate "${TEST_IMAGE_TEMPLATE}" || return $?

  echo "Running e2e tests, directory ./test/e2e_sink/"
  go_test_e2e -timeout=100m -short ./test/e2e_sink/ \
    -imagetemplate "${TEST_IMAGE_TEMPLATE}" || return $?

  echo "Running e2e tests, directory ./test/e2e_source/"
  go_test_e2e -timeout=100m -short ./test/e2e_source/ \
    -imagetemplate "${TEST_IMAGE_TEMPLATE}" || return $?

  echo "Running e2e tests, directory ./test/e2e_channel/"
  go_test_e2e -timeout=100m -short ./test/e2e_channel/ \
    -imagetemplate "${TEST_IMAGE_TEMPLATE}" || return $?
}

function run_conformance_tests() {
  export BROKER_CLASS="Kafka"

  go_test_e2e -timeout=100m ./test/e2e/conformance \
    -imagetemplate "${TEST_IMAGE_TEMPLATE}" || return $?

  go_test_e2e -timeout=100m ./test/e2e_channel/conformance \
    -imagetemplate "${TEST_IMAGE_TEMPLATE}" || return $?
}

function run_e2e_new_tests() {
  export BROKER_CLASS="Kafka"

  if [[ ${FIRST_EVENT_DELAY_ENABLED:-true} == true ]]; then
    ./test/scripts/first-event-delay.sh || return $?
  fi
  go_test_e2e -timeout=100m ./test/e2e_new/... || return $?
  go_test_e2e -timeout=100m ./test/e2e_new_channel/... || return $?
}
