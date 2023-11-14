#!/usr/bin/env bash

function resolve_resources() {
  echo $@

  local dir=$1
  local resolved_file_name=$2
  local image_prefix=$3
  local override=${4:-false}
  local image_name=${5:-""}

  local version=${release/release-/}

  echo "Writing resolved yaml to $resolved_file_name ${version}"

  for yaml in "$dir"/*.yaml; do
    echo "Resolving ${yaml}"

    # 1. Prefix test image references with test-
    # 2. Rewrite image references
    # 3. Remove comment lines
    # 4. Remove empty lines

    if $override; then
      sed -i -e "s+\(.* image: \)\(knative.dev\)\(.*/\)\(test/\)\(.*\)+\1\2 \3\4test-\5+g" \
        -e "s+ko://++" \
        -e "s+app.kubernetes.io/version: devel+app.kubernetes.io/version: ${release}+" \
        -e "s+\(.* image: \)\(knative.dev\)\(.*/\)\(.*\)+\1${image_prefix}-test-\4:${version}+g" \
        -e "s+\(.* image: \)\({{ \.image }}\)\(.*\)+\1${image_prefix}-test-${image_name}:${version}+g" \
        "$yaml"
    else
      echo "---" >>"$resolved_file_name"
      sed -e "s+\(.* image: \)\(knative.dev\)\(.*/\)\(test/\)\(.*\)+\1\2 \3\4test-\5+g" \
        -e "s+ko://++" \
        -e "s+kafka.eventing.knative.dev/release: devel+kafka.eventing.knative.dev/release: ${release}+" \
        -e "s+app.kubernetes.io/version: devel+app.kubernetes.io/version: ${release}+" \
        -e "s+\${KNATIVE_KAFKA_DISPATCHER_IMAGE}+${image_prefix}-dispatcher:${version}+" \
        -e "s+\${KNATIVE_KAFKA_RECEIVER_IMAGE}+${image_prefix}-receiver:${version}+" \
        -e "s+\(.* image: \)\(knative.dev\)\(.*/\)\(.*\)+\1${image_prefix}-\4:${version}+g" \
        "$yaml" >>"$resolved_file_name"
    fi
  done
}
