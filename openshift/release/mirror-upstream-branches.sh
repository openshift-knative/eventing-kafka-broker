#!/usr/bin/env bash

# Usage: openshift/release/mirror-upstream-branches.sh
# This should be run from the basedir of the repo with no arguments


set -ex
readonly TMPDIR=$(mktemp -d knativeEventingBranchingCheckXXXX -p /tmp/)

git fetch upstream --tags
git fetch openshift --tags

# We need to seed this with a few releases that, otherwise, would make
# the processing regex less clear with more anomalies
cat >> "$TMPDIR"/midstream_branches <<EOF
0.2
0.3
EOF

git branch --list -a "upstream/release-*" | cut -f3 -d'/' | cut -f2 -d'-' > "$TMPDIR"/upstream_branches
git branch --list -a "openshift/release-*" | cut -f3 -d'/' | cut -f2 -d'v' | cut -f1,2 -d'.' >> "$TMPDIR"/midstream_branches

sort -o "$TMPDIR"/midstream_branches "$TMPDIR"/midstream_branches
sort -o "$TMPDIR"/upstream_branches "$TMPDIR"/upstream_branches
comm -32 "$TMPDIR"/upstream_branches "$TMPDIR"/midstream_branches > "$TMPDIR"/new_branches

branches=$(cat "$TMPDIR"/new_branches)
UPSTREAM_BRANCHES=($branches)

if [ "${#UPSTREAM_BRANCHES[@]}" == 0 ]; then
    echo "no new branch, exiting"
    exit 0
fi

echo "Found upstream branches: ${UPSTREAM_BRANCHES[@]}"

for branch in "${UPSTREAM_BRANCHES[@]}"; do
  upstream_tag="knative-v${branch}.0"
  # First, try "knative-v" prefix. The upstream tags have a different naming scheme since 1.0
  if ! git ls-remote --tags upstream | grep "${upstream_tag}" &>/dev/null; then
    upstream_tag="v${branch}.0"
  fi
  midstream_branch="release-v${branch}"
  openshift/release/create-release-branch.sh "$upstream_tag" "$midstream_branch"
  # we would check the error code, but we 'set -e', so assume we're fine
  git push openshift "$midstream_branch"
done

