#!/usr/bin/env bash
# Produce the zip the benchmark harness stages as input_001.zip.
set -euo pipefail
cd "$(dirname "$0")"
rm -f myanalysis-fixture.zip
zip -qr myanalysis-fixture.zip myanalysis -x '*.DS_Store'
echo "wrote $(pwd)/myanalysis-fixture.zip"
