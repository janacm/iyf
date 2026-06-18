#!/usr/bin/env bats
# Tests for lib/iyf-show-alert.sh — the canonical alert launcher.

setup() {
  load test_helper
  setup_common
  LAUNCHER="$REPO_ROOT/lib/iyf-show-alert.sh"
}

@test "exits non-zero when the native helper is missing" {
  export IYF_NATIVE_ALERT="$BATS_TEST_TMPDIR/does-not-exist"
  run "$LAUNCHER" "build" "1s" 0
  assert_failure
  assert_output_contains "native helper"
}

@test "launches the native helper with a file:// alert URL" {
  export IYF_REPO="myrepo"
  run "$LAUNCHER" "make test" "2m 3s" 0
  assert_success
  wait_for_file "$IYF_PROBE_OUT" || { echo "helper was never launched"; false; }
  url="$(cat "$IYF_PROBE_OUT")"
  case "$url" in
    file://*"$REPO_ROOT/alert.html"*) : ;;
    *) echo "unexpected url: $url"; false ;;
  esac
}

@test "passes duration, exit code and repo through to the URL" {
  export IYF_REPO="myrepo"
  run "$LAUNCHER" "deploy" "5s" 7
  assert_success
  wait_for_file "$IYF_PROBE_OUT"
  url="$(cat "$IYF_PROBE_OUT")"
  assert_file_contains "$IYF_PROBE_OUT" "code=7"
  assert_file_contains "$IYF_PROBE_OUT" "repo=myrepo"
  assert_file_contains "$IYF_PROBE_OUT" "duration=5s"
}

@test "url-encodes the command label" {
  export IYF_REPO=""
  run "$LAUNCHER" "git commit -m hi" "1s" 0
  assert_success
  wait_for_file "$IYF_PROBE_OUT"
  # spaces -> %20 in the cmd= param
  assert_file_contains "$IYF_PROBE_OUT" "cmd=git%20commit"
}

@test "honors IYF_AUTO_CLOSE in the URL" {
  export IYF_REPO="" IYF_AUTO_CLOSE=42
  run "$LAUNCHER" "x" "1s" 0
  assert_success
  wait_for_file "$IYF_PROBE_OUT"
  assert_file_contains "$IYF_PROBE_OUT" "autoclose=42"
}

@test "with snooze and focus disabled, the URL marks them off" {
  export IYF_REPO=""
  run "$LAUNCHER" "x" "1s" 0
  assert_success
  wait_for_file "$IYF_PROBE_OUT"
  assert_file_contains "$IYF_PROBE_OUT" "snooze=0"
  assert_file_contains "$IYF_PROBE_OUT" "focus=0"
}

@test "writes the launched PID to the configured pid file" {
  export IYF_REPO=""
  run "$LAUNCHER" "x" "1s" 0
  assert_success
  wait_for_file "$IYF_NATIVE_PID_FILE"
  run cat "$IYF_NATIVE_PID_FILE"
  # a bare integer pid
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "fails closed when the native helper exists but is not executable" {
  helper="$BATS_TEST_TMPDIR/iyf-alert-noexec"
  printf '#!/bin/bash\n' > "$helper"   # present, but never chmod +x
  export IYF_NATIVE_ALERT="$helper"
  run "$LAUNCHER" "x" "1s" 0
  assert_failure
  assert_output_contains "native helper"
  refute_file_appears "$IYF_PROBE_OUT"
}

# The native WebKit file:// path can re-escape percent-encoded query values, so
# alert.html prefers the base64url copy for the displayed text — it's the
# load-bearing channel. Assert it round-trips, not just that cmd= looks right.
@test "cmdb64 is a faithful base64url copy of the command" {
  export IYF_REPO=""
  run "$LAUNCHER" 'git commit -m "a&b=c"' "1s" 0
  assert_success
  wait_for_file "$IYF_PROBE_OUT"
  b64="$(sed -n 's/.*cmdb64=\([^&]*\).*/\1/p' "$IYF_PROBE_OUT")"
  [ -n "$b64" ] || { echo "no cmdb64 param in URL:"; cat "$IYF_PROBE_OUT"; false; }
  decoded="$(python3 -c "import base64,sys; s=sys.argv[1]; s+='='*(-len(s)%4); print(base64.urlsafe_b64decode(s).decode())" "$b64")"
  assert_equal "$decoded" 'git commit -m "a&b=c"'
}

# IYF_REPO unset -> auto-detect from git (the path the Claude/Codex hook relies
# on, since it only sets IYF_REPO_DIR). Distinct from explicit-empty below.
@test "auto-detects the repo name from git when IYF_REPO is unset" {
  repo="$BATS_TEST_TMPDIR/myproj"; mkdir -p "$repo"
  git -C "$repo" init -q
  export IYF_REPO_DIR="$repo"   # IYF_REPO is unset (cleared in setup_common)
  run "$LAUNCHER" "x" "1s" 0
  assert_success
  wait_for_file "$IYF_PROBE_OUT"
  assert_file_contains "$IYF_PROBE_OUT" "repo=myproj"
}

@test "explicit empty IYF_REPO hides the badge (repo= stays empty)" {
  export IYF_REPO=""
  export IYF_REPO_DIR="$BATS_TEST_TMPDIR"   # would resolve if the unset branch ran
  git -C "$BATS_TEST_TMPDIR" init -q 2>/dev/null || true
  run "$LAUNCHER" "x" "1s" 0
  assert_success
  wait_for_file "$IYF_PROBE_OUT"
  # repo= is immediately followed by the next param -> empty value, badge hidden
  assert_file_contains "$IYF_PROBE_OUT" "repo=&"
}

# Forward-looking guard for the documented "no browser fallback" guarantee:
# the launcher must never contain code that opens a browser.
@test "launcher never launches a browser (no-fallback guarantee)" {
  run grep -nEi 'open[[:space:]]+-a[[:space:]]*"?(safari|google chrome|brave|microsoft edge|firefox|chromium)|/Applications/(Safari|Google Chrome|Brave Browser|Microsoft Edge|Firefox)\.app' "$LAUNCHER"
  assert_failure   # no match -> grep exits 1 -> guarantee holds
}
