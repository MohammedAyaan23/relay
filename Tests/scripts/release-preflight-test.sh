#!/bin/bash
# Tests that make-release.sh refuses to build from uncommitted changes, using a throwaway clone of this repo.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git clone -q "$REPO" "$WORK/repo"
cd "$WORK/repo"
fail() { echo "FAIL: $1"; exit 1; }

expect_refusal() {
    if output="$(RELAY_SIGN_IDENTITY=- scripts/make-release.sh 2>&1)"; then fail "released with $1"; fi
    [[ "$output" == *"Commit or stash your changes first"* ]] || fail "unexpected message for $1: $output"
    [[ "$output" == *"Compiling"* || "$output" == *"Building"* ]] && fail "it started building with $1"
    return 0
}

echo "stray" > stray.txt
expect_refusal "an untracked file"
rm stray.txt

echo "// edit" >> Package.swift
expect_refusal "a modified file"

echo "PASS: make-release refuses uncommitted changes"
