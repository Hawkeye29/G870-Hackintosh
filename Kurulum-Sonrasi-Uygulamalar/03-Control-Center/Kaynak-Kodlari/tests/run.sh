#!/bin/bash
set -eu
cd "$(dirname "$0")"
TEST_BINARY="$(mktemp /private/tmp/g870-session-test.XXXXXX)"
TEST_POLICY="$(mktemp /private/tmp/g870-policy-test.XXXXXX)"
trap '/bin/rm -f "$TEST_BINARY" "$TEST_POLICY"' EXIT
xcrun clang -Wall -Wextra -Wno-unused-parameter -framework IOKit -framework CoreFoundation session.c -o "$TEST_BINARY"
"$TEST_BINARY"

xcrun clang++ -std=c++14 quiet_policy.cpp -o "$TEST_POLICY"
"$TEST_POLICY"
