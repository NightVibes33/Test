#!/usr/bin/env bash
set -euo pipefail
cp "$GITHUB_WORKSPACE/harness/h1/CacheAuthIsolationTest.php"    "$GITHUB_WORKSPACE/matomo/plugins/ScheduledReports/tests/Integration/CacheAuthIsolationTest.php"
