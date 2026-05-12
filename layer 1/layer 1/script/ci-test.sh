#!/usr/bin/env bash
set -euo pipefail

echo "==> Formatting check"
forge fmt --check

echo "==> Build"
forge build

echo "==> Unit and property tests"
forge test -vv

echo "==> Gas snapshot"
forge snapshot
