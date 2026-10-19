#!/bin/bash
set -eu
cd "$(dirname "$0")"
TEST_DIR="$(mktemp -d /private/tmp/g870-profiles.XXXXXX)"
trap '/bin/rm -rf "$TEST_DIR"' EXIT
python3 - "$TEST_DIR" <<'PY'
from pathlib import Path
import sys
out=Path(sys.argv[1]); src=Path('../src')
(out/'Monitor.swift').write_text((src/'G870Monitor.swift').read_text().split('struct SensorCard: View')[0])
(out/'Curve.swift').write_text((src/'CurveEditor.swift').read_text().split('struct CurveEditor: View')[0])
PY
xcrun swiftc -parse-as-library -module-cache-path "$TEST_DIR/cache" "$TEST_DIR/Monitor.swift" "$TEST_DIR/Curve.swift" ../src/ModeProfile.swift profiles.swift -o "$TEST_DIR/profiles"
"$TEST_DIR/profiles"
