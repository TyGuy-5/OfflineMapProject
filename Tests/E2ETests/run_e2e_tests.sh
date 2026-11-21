#!/usr/bin/env bash
set -e

# run_e2e_tests.sh — Compile and run the opaque-box E2E test suite

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> Compiling MyOfflineMapApp E2E Test Suite..."
TMPDIR=/tmp swiftc -module-cache-path /tmp/clang-cache \
  -O \
  -o /tmp/e2e_runner \
  "$SCRIPT_DIR"/Support/*.swift \
  "$SCRIPT_DIR"/Tier1_FeatureCoverage/*.swift \
  "$SCRIPT_DIR"/Tier2_BoundaryCases/*.swift \
  "$SCRIPT_DIR"/Tier3_PairwiseCombinations/*.swift \
  "$SCRIPT_DIR"/Tier4_RealWorldScenarios/*.swift \
  "$SCRIPT_DIR"/Runner/TestRunner.swift \
  "$SCRIPT_DIR"/Runner/main.swift

echo "==> Executing E2E Test Runner..."
/tmp/e2e_runner
