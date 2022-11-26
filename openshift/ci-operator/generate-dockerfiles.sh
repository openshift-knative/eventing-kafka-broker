#!/bin/bash

set -e

# shellcheck disable=SC2002
go_version=$(grep "^go.*" "go.mod" | awk '{print $2}')
dockerfile_replace="s|registry.ci.openshift.org/openshift/release:golang-[a-zA-Z0-9.]*|registry.ci.openshift.org/openshift/release:golang-${go_version}|g"

function generate_dockefiles() {
  local target_dir=$1; shift
  sed -i "${dockerfile_replace}" "openshift/ci-operator/build-image/Dockerfile"
  sed -i "${dockerfile_replace}" "openshift/ci-operator/Dockerfile.in"
  # Remove old images and re-generate, avoid stale images hanging around.
  for img in $@; do
    local image_base=$(basename $img)
    mkdir -p $target_dir/$image_base
    bin=$image_base envsubst < openshift/ci-operator/Dockerfile.in > $target_dir/$image_base/Dockerfile
  done
}

generate_dockefiles $@
