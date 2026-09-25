#!/usr/bin/env bash
# Fetch one URL, with a hard ceiling on how much of the answer is read.
#
#   FETCH_URL=<url> fetch.sh <max-seconds> [curl options...]
#
# The URL comes in through the environment and reaches curl through a config
# file descriptor, never as an argument: any local user can read every
# process's command line (/proc/<pid>/cmdline), but only we can read its
# environment or file descriptors, and which status pages someone watches is
# theirs to keep. Nothing on this script's or curl's command line is private.
#
# Prints the response body, or nothing and exits non-zero when the request
# fails, runs past <max-seconds>, or the body is larger than MAX_BYTES. A
# failed request exits with curl's own code, so a caller can still tell an
# HTTP error (22) from a network failure; an oversized body exits 63, which is
# what curl itself uses for a download over --max-filesize.
#
# Every status feed the widget parses comes through here, and the URLs are
# whatever the user pasted, so a broken or hostile page must not make the
# shell's StdioCollector buffer an unbounded body. At most MAX_BYTES + 1 bytes
# are ever read: a body that reaches that extra byte is too large and is
# dropped before anything parses it. curl's --max-filesize stops such a
# download early too, but it is not trusted on its own, since a server can lie
# about or omit the length.
#
# The largest preset feed was ~270 KB when this was written (Elastic, Snowflake,
# Twilio and Cloudflare all run past 200 KB), and a feed grows during an
# incident, so the ceiling leaves about four times that.

set -uo pipefail

MAX_BYTES=1048576

seconds=$1
shift
url=${FETCH_URL-}
# normalizePageUrl only ever produces printable URLs; refuse anything else
# rather than let it reach curl's config syntax.
[[ -n $url && $url != *[[:cntrl:]]* ]] || exit 2
url=${url//\\/\\\\}
url=${url//\"/\\\"}

body=$(mktemp) || exit 1
trap 'rm -f "$body"' EXIT

curl -fsS --max-time "$seconds" --max-filesize "$MAX_BYTES" "$@" \
  --config <(printf 'url = "%s"\n' "$url") 2>/dev/null </dev/null |
  head -c $((MAX_BYTES + 1)) >"$body"
status=("${PIPESTATUS[@]}")

size=$(stat -c %s "$body") || exit 1
((size <= MAX_BYTES)) || exit 63
((status[0] == 0)) || exit "${status[0]}"
((status[1] == 0)) || exit 1

cat "$body"
