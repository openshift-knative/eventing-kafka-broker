#!/usr/bin/env bash

export EVENTING_NAMESPACE="${EVENTING_NAMESPACE:-knative-eventing}"
export SYSTEM_NAMESPACE=$EVENTING_NAMESPACE
export TRACING_NAMESPACE=$EVENTING_NAMESPACE
export KNATIVE_DEFAULT_NAMESPACE=$EVENTING_NAMESPACE

export SKIP_GENERATE_RELEASE=${SKIP_GENERATE_RELEASE:-false}

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

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

export TEST_IMAGE_TEMPLATE=${TEST_IMAGE_TEMPLATE:-$default_test_image_template}

# shellcheck disable=SC1090
source "${SCRIPT_DIR}/../test/e2e-common.sh"

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

function install_serverless() {
  header "Installing Serverless Operator"

  cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: knative-eventing
EOF

  ./test/kafka/kafka_setup.sh || return $?

  ( # Do not leak sensitive information to logs.
    set +x
    create_sasl_secrets || return $?
    create_tls_secrets || return $?
  )

  KNATIVE_EVENTING_KAFKA_BROKER_MANIFESTS_DIR="$(pwd)/openshift/release/artifacts"
  export KNATIVE_EVENTING_KAFKA_BROKER_MANIFESTS_DIR

  local operator_dir=/tmp/serverless-operator
  git clone --branch main https://github.com/openshift-knative/serverless-operator.git $operator_dir
  export GOPATH=/tmp/go
  local failed=0
  pushd $operator_dir || return $?
  export ON_CLUSTER_BUILDS=true
  export DOCKER_REPO_OVERRIDE=image-registry.openshift-image-registry.svc:5000/openshift-marketplace
  if [[ -z "${INSTALL_KEDA}" ]] || [[ "${INSTALL_KEDA}" != "true" ]]; then
  	make OPENSHIFT_CI="true" TRACING_BACKEND=zipkin \
	  generated-files images install-tracing install-kafka || failed=$?
  else
	make OPENSHIFT_CI="true" TRACING_BACKEND=zipkin \
	  generated-files images install-tracing install-kafka-with-keda || failed=$?
  fi
  popd || return $?

  oc apply -f openshift/knative-eventing.yaml
  oc wait --for=condition=Ready knativeeventing.operator.knative.dev knative-eventing -n knative-eventing --timeout=900s

  local openshift_version=$(oc version -o yaml | yq read - openshiftVersion)
  local cert_manager_namespace="cert-manager"
  if printf '%s\n4.12\n' "${openshift_version}" | sort --version-sort -C; then
      # OCP version is older as 4.12 and thus cert-manager-operator is only available as tech-preview in this version (cert-manager-operator GA'ed in OCP 4.12)
      echo "Running on OpenShift ${openshift_version} which supports cert-manager-operator only in tech-preview"
      cert_manager_namespace="openshift-cert-manager"
  else
    echo "Running on OpenShift ${openshift_version} which supports GA'ed cert-manager-operator"
  fi

  oc apply \
    -f "${SCRIPT_DIR}/tls/issuers/eventing-ca-issuer.yaml" \
    -f "${SCRIPT_DIR}/tls/issuers/selfsigned-issuer.yaml" || return $?

  oc apply -n "${cert_manager_namespace}" -f "${SCRIPT_DIR}/tls/issuers/ca-certificate.yaml" || return $?

  local ca_cert_tls_secret="knative-eventing-ca"
  echo "Waiting until secrets: ${ca_cert_tls_secret} exist in ${cert_manager_namespace}"
  wait_until_object_exists secret "${ca_cert_tls_secret}" "${cert_manager_namespace}" || return $?

  oc get secret -n "${cert_manager_namespace}" "${ca_cert_tls_secret}" -o=jsonpath='{.data.tls\.crt}' | base64 -d > tls.crt || return $?
  oc get secret -n "${cert_manager_namespace}" "${ca_cert_tls_secret}" -o=jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt || return $?
  oc create configmap -n knative-eventing knative-eventing-bundle --from-file=tls.crt --from-file=ca.crt \
    --dry-run=client -o yaml | kubectl apply -n knative-eventing -f - || return $?

  oc label configmap -n knative-eventing knative-eventing-bundle networking.knative.dev/trust-bundle=true

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
  local common_opts
  export BROKER_CLASS="Kafka"

  if [ "$SKIP_GENERATE_RELEASE" = false ]; then
    make generate-release
  fi

  images_file="${SCRIPT_DIR}"/images.yaml
  cat "${images_file}"

  if [[ ${FIRST_EVENT_DELAY_ENABLED:-true} == true ]]; then
    ./test/scripts/first-event-delay.sh || return $?
  fi

  common_opts=(--images.producer.file="${images_file}" --poll.timeout=8m)

  go_test_e2e -timeout=100m ./test/e2e_new/... "${common_opts[@]}" || return $?
  go_test_e2e -timeout=100m ./test/e2e_new_channel/... "${common_opts[@]}" || return $?
}

function run_e2e_encryption_auth_tests(){
  header "Running E2E Encryption and Auth Tests"

  oc patch knativeeventing --type merge -n "${EVENTING_NAMESPACE}" knative-eventing --patch-file "${SCRIPT_DIR}/knative-eventing-encryption-auth.yaml"

  images_file=$(dirname $(realpath "$0"))/images.yaml
  make generate-release
  cat "${images_file}"

  oc wait --for=condition=Ready knativeeventing.operator.knative.dev knative-eventing -n "${EVENTING_NAMESPACE}" --timeout=900s || return $?

  local regex="TLS"

  local test_name="${1:-}"
  local run_command="-run ${regex}"
  local failed=0

  if [ -n "$test_name" ]; then
      local run_command="-run ^(${test_name})$"
  fi
  # check for test flags
  RUN_FLAGS="-timeout=1h -parallel=20 -run ${regex}"
  go_test_e2e ${RUN_FLAGS} ./test/e2e_new --images.producer.file="${images_file}" || failed=$?

  return $failed
}
