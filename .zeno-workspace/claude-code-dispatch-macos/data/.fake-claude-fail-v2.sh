#!/usr/bin/env bash
set -euo pipefail
echo 'fake claude: fail start'
sleep 1
echo 'unable to connect to upstream'
sleep 1
exit 7
