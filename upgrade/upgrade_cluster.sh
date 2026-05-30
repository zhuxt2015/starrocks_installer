#!/bin/bash
set -eu
bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/upgrade.sh" all
