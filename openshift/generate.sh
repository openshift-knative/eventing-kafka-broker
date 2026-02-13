#!/usr/bin/env bash

set -euo pipefail

repo_root_dir=$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..

GOFLAGS='' go run github.com/openshift-knative/hack/cmd/generate@latest \
  --root-dir "${repo_root_dir}" \
  --generators dockerfile

# Update CPE labels in the static Dockerfiles with computed versions
release=$(yq r "${repo_root_dir}/openshift/project.yaml" project.tag)
release=${release/knative-/}

so_branch=$( GOFLAGS='' go run github.com/openshift-knative/hack/cmd/sobranch@latest --upstream-version "${release}")
so_release=${so_branch/release-/}

rhel_version=$( GOFLAGS='' go run github.com/openshift-knative/hack/cmd/sorhel@latest --so-version "${so_release}")

for dockerfile in openshift/ci-operator/static-images/*/hermetic/Dockerfile; do
  if [ -f "$dockerfile" ]; then
    sed -i "s|cpe=\"cpe:/a:redhat:openshift_serverless:[^\"]*\"|cpe=\"cpe:/a:redhat:openshift_serverless:${so_release}::el${rhel_version}\"|g" "$dockerfile"
  fi
done