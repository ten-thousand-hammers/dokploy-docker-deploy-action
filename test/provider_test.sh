#!/usr/bin/env bash
# Exercises the "Save Docker Provider Configuration" step from action.yml against
# a mocked Dokploy API. The step is extracted from the action rather than copied,
# so the test always runs the code the action actually ships.
#
# The behaviour that matters: saveDockerProvider is a partial update, so any
# registry field sent with an empty value overwrites real credentials stored on
# the application and the next deploy cannot pull a private image.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
LAST_DIR_FILE="/tmp/provider_test_lastdir"
MOCK_CODE=200

extract_step() {
  python3 - "$ROOT/action.yml" "$1" <<'PY'
import sys, yaml
action, name = sys.argv[1], sys.argv[2]
steps = yaml.safe_load(open(action))["runs"]["steps"]
step = next(s for s in steps if s.get("name") == name)
sys.stdout.write(step["run"])
PY
}

# run_save <app ids>; optional RU/RP/RURL/MOCK_CODE env
run_save() {
  local app_ids="$1"
  local dir; dir="$(mktemp -d)"
  mkdir -p "$dir/bin"

  cat > "$dir/bin/curl" <<'MOCK'
#!/usr/bin/env bash
count=0
[[ -f "$MOCK_DIR/count" ]] && count="$(< "$MOCK_DIR/count")"
count=$((count + 1))
echo "$count" > "$MOCK_DIR/count"
prev=""
for arg in "$@"; do
  [[ "$prev" == "-d" ]] && printf '%s' "$arg" > "$MOCK_DIR/payload-$count.json"
  prev="$arg"
done
printf '\n%s' "${MOCK_CODE:-200}"
MOCK
  chmod +x "$dir/bin/curl"

  : > "$dir/github_env"
  printf '%s\n' $app_ids > /tmp/app_ids.txt

  PATH="$dir/bin:$PATH" \
  MOCK_DIR="$dir" \
  MOCK_CODE="${MOCK_CODE}" \
  GITHUB_ENV="$dir/github_env" \
  DOKPLOY_HOST="https://dokploy.example.test" \
  DOKPLOY_TOKEN="test-token" \
  DOCKER_REGISTRY="ghcr.io/example/app" \
  DOCKER_TAG="2026.8.2-1" \
  REGISTRY_USERNAME="${RU:-}" \
  REGISTRY_PASSWORD="${RP:-}" \
  REGISTRY_URL="${RURL:-}" \
  "${BASH:-bash}" -c "$(extract_step 'Save Docker Provider Configuration')" 2>&1
  local code=$?
  printf '%s' "$dir" > "$LAST_DIR_FILE"
  return $code
}

# assert <label> <python expression using d (payload dict)>
assert_payload() {
  local label="$1" expr="$2" file="${3:-payload-1.json}"
  local ok=0
  local base; base="$(cat "$LAST_DIR_FILE" 2>/dev/null)"
  local payload="$base/$file"
  if [[ ! -f "$payload" ]]; then
    echo "  FAIL $label"; echo "    no payload written ($file)"; FAIL=$((FAIL+1)); return
  fi
  python3 - "$payload" "$expr" <<'PY' && ok=1
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if eval(sys.argv[2]) else 1)
PY
  if [[ $ok -eq 1 ]]; then echo "  OK   $label"; PASS=$((PASS+1));
  else echo "  FAIL $label"; echo "    payload: $(cat "$payload")"; FAIL=$((FAIL+1)); fi
}

check() {
  local label="$1" expected_status="$2" output="$3" actual_status="$4"; shift 4
  local ok=1
  [[ "$actual_status" == "$expected_status" ]] || { ok=0; echo "    expected exit $expected_status, got $actual_status"; }
  for needle in "$@"; do
    if [[ "$output" != *"$needle"* ]]; then ok=0; echo "    missing: $needle"; fi
  done
  if [[ $ok -eq 1 ]]; then echo "  OK   $label"; PASS=$((PASS+1));
  else echo "  FAIL $label"; echo "$output" | sed 's/^/      | /'; FAIL=$((FAIL+1)); fi
}

echo "dokploy save docker provider"

# No credentials supplied: the registry fields must be absent entirely, so
# credentials already stored on the application survive.
out="$(run_save app1)"; st=$?
check "omits registry fields when no credentials are supplied" 0 "$out" $st \
  "leaving any stored on the application alone" "saved successfully"
assert_payload "payload carries the image and the application id" \
  "d['dockerImage'] == 'ghcr.io/example/app:2026.8.2-1' and d['applicationId'] == 'app1'"
assert_payload "payload has no username key" "'username' not in d"
assert_payload "payload has no password key" "'password' not in d"
assert_payload "payload has no registryUrl key" "'registryUrl' not in d"

# Credentials supplied: sent, with the registry host derived from the image.
RU="bot" RP="s3cret-token" out="$(run_save app1)"; st=$?
check "sends supplied credentials" 0 "$out" $st "sending registry credentials for ghcr.io as bot"
assert_payload "payload carries the username" "d['username'] == 'bot'"
assert_payload "payload carries the password" "d['password'] == 's3cret-token'"
assert_payload "registry host defaults to the image registry" "d['registryUrl'] == 'ghcr.io'"
if [[ "$out" == *"s3cret-token"* ]]; then
  echo "  FAIL password is echoed into the log"; FAIL=$((FAIL+1))
else
  echo "  OK   password is not echoed into the log"; PASS=$((PASS+1))
fi

# An explicit registry host wins over the derived one.
RU="bot" RP="s3cret-token" RURL="https://index.docker.io/v1/" out="$(run_save app1)"; st=$?
check "honours an explicit REGISTRY_URL" 0 "$out" $st "for https://index.docker.io/v1/"
assert_payload "payload carries the explicit registry url" "d['registryUrl'] == 'https://index.docker.io/v1/'"

# Every application gets its own write.
out="$(run_save "app1 app2")"; st=$?
check "writes once per application" 0 "$out" $st "app1" "app2"
assert_payload "second application gets its own payload" "d['applicationId'] == 'app2'" payload-2.json

# A non-200 from Dokploy fails the step.
MOCK_CODE=500
out="$(run_save app1)"; st=$?
MOCK_CODE=200
check "fails when Dokploy rejects the write" 1 "$out" $st "HTTP Status: 500" "Failed to save Docker provider configuration"

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
