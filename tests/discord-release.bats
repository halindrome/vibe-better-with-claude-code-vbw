#!/usr/bin/env bats
# The Discord release post (tools/post-discord-release.sh, run by
# .github/workflows/discord-release.yml when a GitHub release is published):
# the webhook receives the whole payload the script builds, whatever the notes
# hold. Notes within Discord's embed limit (4096 characters) go as one JSON
# post; longer notes go as a multipart post whose payload_json carries the
# truncated description and whose attachment holds the full notes. curl cuts a
# plain -F value at its first ';' (the start of a form-field option), so a
# payload with a semicolon has to reach curl as a literal form string (release
# v2.1.16, 2026-10-26: HTTP 400, payload_json not valid JSON). L1: the script
# against a fake curl that applies curl's own rule for -F values.

load helper

setup() {
  vbw_setup
  mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/out"
  cat > "$TEST_ROOT/bin/curl" <<'FAKE'
#!/bin/bash
# A stand-in for curl: records the payload it would send. A -F value is cut at
# its first ';', as curl parses a form-field option there; --form-string and -d
# are taken whole. Prints 200 for -w '%{http_code}'.
out=$FAKE_OUT
while [ $# -gt 0 ]; do
  case "$1" in
    -F)
      v=$2; shift
      case "$v" in
        payload_json=*) v=${v#payload_json=}; printf '%s' "${v%%;*}" > "$out/payload"; printf 'form\n' > "$out/mode" ;;
        'files[0]=@'*) v=${v#files\[0\]=@}; cp "${v%%;*}" "$out/file" ;;
      esac ;;
    --form-string)
      v=$2; shift
      case "$v" in payload_json=*) printf '%s' "${v#payload_json=}" > "$out/payload"; printf 'form\n' > "$out/mode" ;; esac ;;
    -d) printf '%s' "$2" > "$out/payload"; printf 'json\n' > "$out/mode"; shift ;;
    -D | -o | -H | -w) shift ;;
  esac
  shift
done
printf '200'
FAKE
  chmod +x "$TEST_ROOT/bin/curl"
}
teardown() { vbw_teardown; }

# post BODY: runs the script with BODY as the release notes against the fake curl.
post() {
  WEBHOOK_URL='https://discord.test/api/webhooks/1/x' RELEASE_TAG='v9.9.9' RELEASE_NAME='v9.9.9' \
    RELEASE_URL='https://example.test/releases/v9.9.9' RELEASE_BODY="$1" \
    CURL_BIN="$TEST_ROOT/bin/curl" FAKE_OUT="$TEST_ROOT/out" bash "$REPO_ROOT/tools/post-discord-release.sh"
}

@test "notes within the embed limit go as one JSON post holding them whole" {
  local body='## Added

- **Fast checks.** A proof reuses its last results; a change re-runs what it touches (L1; L3 on request).'
  run post "$body"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$TEST_ROOT/out/mode")" = json ]
  jq -e --arg b "$body" '.embeds[0].description == $b and .embeds[0].title == "Release v9.9.9"' "$TEST_ROOT/out/payload" \
    || { cat "$TEST_ROOT/out/payload"; false; }
  [ ! -e "$TEST_ROOT/out/file" ]
}

@test "notes over the embed limit go as a multipart post: payload_json is the whole JSON, semicolons included, and the attachment holds the full notes" {
  local body='' i
  for i in $(seq 1 200); do body="$body- point $i: proven first; shipped after (L1; L3)
"; done
  [ "${#body}" -gt 4096 ]
  run post "$body"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$TEST_ROOT/out/mode")" = form ]
  jq -e '.embeds[0].description | (contains("proven first; shipped after (L1; L3)") and endswith("Full release notes attached as `release-notes.md`."))' \
    "$TEST_ROOT/out/payload" || { head -c 300 "$TEST_ROOT/out/payload"; echo; false; }
  [ "$(cat "$TEST_ROOT/out/file")" = "$(printf '%s' "$body")" ] || { echo "the attachment is not the notes"; false; }
}
