#!/usr/bin/env bash

export EVENTING_NAMESPACE="${EVENTING_NAMESPACE:-knative-eventing}"
export SYSTEM_NAMESPACE=$EVENTING_NAMESPACE
export ZIPKIN_NAMESPACE=$EVENTING_NAMESPACE
export KNATIVE_DEFAULT_NAMESPACE=$EVENTING_NAMESPACE
export EVENTING_KAFKA_BROKER_TEST_IMAGE_TEMPLATE=$(
  cat <<-END
{{- with .Name }}
{{- if eq . "event-sender"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_EVENT_SENDER{{end -}}
{{- if eq . "heartbeats"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_HEARTBEATS{{end -}}
{{- if eq . "eventshub"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_EVENTSHUB{{end -}}
{{- if eq . "recordevents"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_RECORDEVENTS{{end -}}
{{- if eq . "print"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_PRINT{{end -}}
{{- if eq . "performance"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_PERFORMANCE{{end -}}
{{- if eq . "event-flaker"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_EVENT_FLAKER{{end -}}
{{- if eq . "event-library"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_EVENT_LIBRARY{{end -}}
{{- if eq . "committed-offset"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_COMMITTED_OFFSET{{end -}}
{{- if eq . "consumer-group-lag-provider-test"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_CONSUMER_GROUP_LAG_PROVIDER_TEST{{end -}}
{{- if eq . "kafka-consumer"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_KAFKA_CONSUMER{{end -}}
{{- if eq . "partitions-replication-verifier"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_PARTITIONS_REPLICATION_VERIFIER{{end -}}
{{- if eq . "request-sender"}}$KNATIVE_EVENTING_KAFKA_BROKER_TEST_REQUEST_SENDER{{end -}}
{{end -}}
END
)

function scale_up_workers() {
  local cluster_api_ns="openshift-machine-api"

  oc get machineset -n ${cluster_api_ns} --show-labels

  # Get the name of the first machineset that has at least 1 replica
  local machineset
  machineset=$(oc get machineset -n ${cluster_api_ns} -o custom-columns="name:{.metadata.name},replicas:{.spec.replicas}" | grep " 1" | head -n 1 | awk '{print $1}')
  # Bump the number of replicas to 6 (+ 1 + 1 == 8 workers)
  oc patch machineset -n ${cluster_api_ns} "${machineset}" -p '{"spec":{"replicas":6}}' --type=merge
  wait_until_machineset_scales_up ${cluster_api_ns} "${machineset}" 6
}

# Waits until the machineset in the given namespaces scales up to the
# desired number of replicas
# Parameters: $1 - namespace
#             $2 - machineset name
#             $3 - desired number of replicas
function wait_until_machineset_scales_up() {
  echo -n "Waiting until machineset $2 in namespace $1 scales up to $3 replicas"
  for _ in {1..150}; do # timeout after 15 minutes
    local available
    available=$(oc get machineset -n "$1" "$2" -o jsonpath="{.status.availableReplicas}")
    if [[ ${available} -eq $3 ]]; then
      echo -e "\nMachineSet $2 in namespace $1 successfully scaled up to $3 replicas"
      return 0
    fi
    echo -n "."
    sleep 6
  done
  echo - "Error: timeout waiting for machineset $2 in namespace $1 to scale up to $3 replicas"
  return 1
}

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

  KNATIVE_EVENTING_KAFKA_BROKER_MANIFESTS_DIR="$(pwd)/openshift/release/artifacts"
  export KNATIVE_EVENTING_KAFKA_BROKER_MANIFESTS_DIR

  local operator_dir=/tmp/serverless-operator
  git clone --branch main https://github.com/openshift-knative/serverless-operator.git $operator_dir
  export GOPATH=/tmp/go
  local failed=0
  pushd $operator_dir || return $?
  OPENSHIFT_CI="true" make generated-files install-operator || failed=$?
  popd || return $?

  local eventing_cr="$(mktemp -t eventing-XXXXX.yaml)"
  cp openshift/knative-eventing.yaml "$eventing_cr"
  enable_tracing "$eventing_cr"
  oc apply -f "$eventing_cr"

  # Install KnativeKafka after installing KnativeEventing with tracing enabled
  oc apply -f openshift/knative-kafka.yaml

  oc wait --for=condition=Ready knativekafkas.operator.serverless.openshift.io knative-kafka -n knative-eventing --timeout=900s
  oc wait --for=condition=Ready knativeeventing.operator.knative.dev knative-eventing -n knative-eventing --timeout=900s

  return $failed
}

function run_e2e_tests() {

  go_test_e2e -timeout=100m -short ./test/e2e/ \
    -imagetemplate "${TEST_IMAGE_TEMPLATE}" || return $?

  go_test_e2e -timeout=100m -short ./test/e2e_channel/ \
    -imagetemplate "${TEST_IMAGE_TEMPLATE}" || return $?
}

function run_conformance_tests() {
  go_test_e2e -timeout=100m ./test/e2e/conformance \
    -imagetemplate "${TEST_IMAGE_TEMPLATE}" || return $?

  go_test_e2e -timeout=100m ./test/e2e_channel/conformance \
    -imagetemplate "${TEST_IMAGE_TEMPLATE}" || return $?
}

function run_e2e_new_tests() {
  ./test/scripts/first-event-delay.sh || return $?
  go_test_e2e -timeout=100m ./test/e2e_new/... || return $?
  go_test_e2e -timeout=100m ./test/e2e_new_channel/... || return $?
}

function deploy_zipkin {
  header "Installing Zipkin in namespace ${ZIPKIN_NAMESPACE}"
  cat <<EOF | oc apply -f - || return $?
apiVersion: v1
kind: Service
metadata:
  name: zipkin
  namespace: ${ZIPKIN_NAMESPACE}
spec:
  type: NodePort
  ports:
  - name: http
    port: 9411
  selector:
    app: zipkin
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zipkin
  namespace: ${ZIPKIN_NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: zipkin
  template:
    metadata:
      labels:
        app: zipkin
      annotations:
        sidecar.istio.io/inject: "false"
    spec:
      containers:
      - name: zipkin
        image: ghcr.io/openzipkin/zipkin:2
        ports:
        - containerPort: 9411
        env:
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: metadata.namespace
        resources:
          limits:
            memory: 1000Mi
          requests:
            memory: 256Mi
---
EOF

  echo ">> Waiting until Zipkin is available"
  kubectl wait deployment --all --timeout=600s --for=condition=Available -n ${ZIPKIN_NAMESPACE} || return 1
}

function enable_tracing {
  local custom_resource tracing_endpoint tracing_patch
  custom_resource=${1:?Pass a custom resource to be patched as arg[1]}

  tracing_patch="$(mktemp -t tracing-XXXXX.yaml)"
  cat - << EOF > "$tracing_patch"
spec:
  config:
    tracing:
      backend: zipkin
      debug: "true"
      enable: "true"
      sample-rate: "1.0"
      zipkin-endpoint: "http://zipkin.${ZIPKIN_NAMESPACE}.svc.cluster.local:9411/api/v2/spans"
EOF

  yq merge --inplace --arrays=append --overwrite "$custom_resource" "$tracing_patch"

  rm -f "${tracing_patch}"
}
