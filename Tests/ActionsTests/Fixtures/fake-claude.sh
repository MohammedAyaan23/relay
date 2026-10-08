#!/bin/sh
# Stand-in for the claude CLI in tests. Records its arguments in ./args.txt (the working
# directory is the project folder), then behaves according to the prompt (the last argument, after --).
here=$(cd "$(dirname "$0")" && pwd)
printf '%s\n' "$@" > args.txt
for prompt in "$@"; do :; done
case "$prompt" in
  ok)
    cat "$here/stream-success.jsonl" ;;
  denied)
    cat "$here/stream-denied.jsonl" ;;
  bad-resume)
    echo "No conversation found with session ID: stale-session" >&2
    cat "$here/stream-bad-resume.jsonl"
    exit 1 ;;
  crash)
    head -n 2 "$here/stream-success.jsonl"
    echo "segfault-ish failure" >&2
    exit 2 ;;
  slow)
    head -n 2 "$here/stream-success.jsonl"
    trap 'exit 130' INT
    sleep 30 &
    wait ;;
  stubborn)
    # Ignores Ctrl-C like a stuck job; only terminate stops it.
    head -n 2 "$here/stream-success.jsonl"
    trap '' INT
    trap 'exit 143' TERM
    while :; do sleep 0.1; done ;;
  *)
    echo "unknown test prompt: $prompt" >&2
    exit 64 ;;
esac
