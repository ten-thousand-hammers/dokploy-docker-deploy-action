#!/usr/bin/env bash
# Exercises the "Wait for deployments" step from action.yml against a mocked
# Dokploy API. The step is extracted from the action rather than copied, so the
# test always runs the code the action actually ships.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

extract_step() {
  python3 - "$ROOT/action.yml" "$1" <<'PY'
import sys, yaml
action, name = sys.argv[1], sys.argv[2]
steps = yaml.safe_load(open(action))["runs"]["steps"]
step = next(s for s in steps if s.get("name") == name)
sys.stdout.write(step["run"])
PY
}

# Each argument is a JSON array: the deployment list returned by successive
# calls to /api/deployment.all.
run_wait() {
  local app_ids="$1"; shift
  local dir; dir="$(mktemp -d)"
  mkdir -p "$dir/bin"

  cat > "$dir/bin/curl" <<'MOCK'
#!/usr/bin/env bash
counter="$MOCK_DIR/counter"
count=0
[[ -f "$counter" ]] && count="$(< "$counter")"
count=$((count + 1))
echo "$count" > "$counter"
response="$MOCK_DIR/response-$count.json"
[[ -f "$response" ]] || exit 1
cat "$response"
MOCK
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/bin/sleep"
  chmod +x "$dir/bin/curl" "$dir/bin/sleep"

  local i=1
  for response in "$@"; do
    printf '%s' "$response" > "$dir/response-$i.json"
    i=$((i + 1))
  done

  printf '%s\n' $app_ids > /tmp/app_ids.txt
  for id in $app_ids; do printf '["old"]' > "/tmp/baseline_${id}.json"; done

  PATH="$dir/bin:$PATH" \
  MOCK_DIR="$dir" \
  DOKPLOY_HOST="https://dokploy.example.test" \
  DOKPLOY_TOKEN="test-token" \
  DOCKER_TAG="2026.8.2-1" \
  WAIT_ATTEMPTS="5" \
  WAIT_INTERVAL_SECONDS="0" \
  "${BASH:-bash}" -c "$(extract_step 'Wait for deployments')" 2>&1
  local code=$?
  rm -rf "$dir"
  return $code
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

deployment() { printf '{"deploymentId":"%s","title":"Deploying 2026.8.2-1","status":"%s","createdAt":"%s"}' "$1" "$2" "$3"; }

OLD="$(deployment old done 2026-08-02T12:00:00Z)"
RUNNING="$(deployment new running 2026-08-02T12:01:00Z)"
DONE="$(deployment new done 2026-08-02T12:01:00Z)"
FAILED="$(printf '{"deploymentId":"new","title":"Deploying 2026.8.2-1","status":"error","createdAt":"2026-08-02T12:01:00Z","errorMessage":"Swarm update failed"}')"

echo "dokploy wait"

out="$(run_wait "app1" "[$OLD]" "[$OLD,$RUNNING]" "[$OLD,$DONE]")"; st=$?
check "ignores an older successful deployment and waits for the new one" 0 "$out" $st \
  "Waiting for Dokploy to create the deployment" "is running" "is done" "reached done"

out="$(run_wait "app1" "[$FAILED]")"; st=$?
check "fails when the new deployment fails" 1 "$out" $st "Swarm update failed" "did not deploy"

out="$(run_wait "app1" "[$OLD]" "[$OLD]" "[$OLD]" "[$OLD]" "[$OLD]")"; st=$?
check "times out when no new deployment ever appears" 1 "$out" $st "Waiting for Dokploy" "did not deploy"

# Two applications: the second must be waited on even though the first is done.
out="$(run_wait "app1 app2" "[$DONE]" "[$RUNNING]" "[$DONE]")"; st=$?
check "waits on every application, not just the first" 0 "$out" $st "app1 deployed" "app2 deployed" "reached done"

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
