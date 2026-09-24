#!/bin/sh
# Stand-in for the claude CLI in tests. Records its arguments in ./args.txt (the working
# directory is the project folder), then behaves according to the prompt (the argument after -p).
here=$(cd "$(dirname "$0")" && pwd)
printf '%s\n' "$@" > args.txt
case "$2" in
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
  *)
    echo "unknown test prompt: $2" >&2
    exit 64 ;;
esac
