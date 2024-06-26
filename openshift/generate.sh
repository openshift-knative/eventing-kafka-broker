#!/usr/bin/env bash

set -euo pipefail

repo_root_dir=$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..

# make sure we install the latest version
rm -f $(go env GOPATH)/bin/generate
GO111MODULE=off go install github.com/openshift-knative/hack/cmd/generate

$(go env GOPATH)/bin/generate \
  --root-dir "${repo_root_dir}" \
  --generators dockerfile
