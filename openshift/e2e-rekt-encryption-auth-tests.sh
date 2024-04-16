#!/usr/bin/env bash

# shellcheck disable=SC1090
source "$(dirname "$0")/e2e-common.sh"

set -Eeuox pipefail

failed=0

(( !failed )) && install_serverless || failed=1

(( !failed )) && run_e2e_encryption_auth_tests || failed=1

(( failed )) && dump_cluster_state

(( failed )) && exit 1

success
