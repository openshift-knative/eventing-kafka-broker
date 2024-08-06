#!/usr/bin/env bash

set -euo pipefail

repo_root_dir=$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..

hack_tmp_dir=$(mktemp -d)
git clone --branch main https://github.com/openshift-knative/hack "$hack_tmp_dir"
pushd "$hack_tmp_dir" || return $?
go install github.com/openshift-knative/hack/cmd/generate
popd || return $?
rm -rf "$hack_tmp_dir"

$(go env GOPATH)/bin/generate \
  --root-dir "${repo_root_dir}" \
  --generators dockerfile
