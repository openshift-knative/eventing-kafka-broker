#!/bin/bash

# Usage: create-release-branch.sh v0.4.1 release-0.4

set -ex # Exit immediately on error.

release=$1
target=$2

# Fetch the latest tags and checkout a new branch from the wanted tag.
git fetch upstream -v --tags
git checkout -b "$target" "$release"

# Remove GH Action hooks from upstream
rm -rf .github/workflows
git commit -sm ":fire: remove unneeded workflows" .github/

# Copy the openshift extra files from the OPENSHIFT/main branch.
git fetch openshift main
git checkout openshift/main -- .github/workflows openshift OWNERS Makefile

git apply openshift/patches/*

# Generate our OCP artifacts
tag=${target/release-/}
yq write --inplace openshift/project.yaml project.tag "knative-$tag"
make generate-release
git add .
git commit -m "Add openshift specific files."
