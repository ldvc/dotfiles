#!/usr/bin/env bats
# Tests for dot_claude/hooks/context-nudge.sh: UserPromptSubmit nudge to /clear past 200k tokens.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$REPO_ROOT/dot_claude/hooks/context-nudge.sh"
  FIX="$BATS_TEST_DIRNAME/fixtures"
}

nudge() {
  printf '{"hook_event_name":"UserPromptSubmit","transcript_path":"%s"}' "$1" | bash "$HOOK"
}

@test "silent below 200k, ignoring a larger sidechain turn" {
  run --separate-stderr nudge "$FIX/transcript_small.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "emits UserPromptSubmit additionalContext from the last main-chain turn" {
  run --separate-stderr nudge "$FIX/transcript_large.jsonl"
  [ "$status" -eq 0 ]
  [ "$(jq -r .hookSpecificOutput.hookEventName <<<"$output")" = "UserPromptSubmit" ]
  ctx="$(jq -r .hookSpecificOutput.additionalContext <<<"$output")"
  [[ "$ctx" == "Context is 369k tokens."* ]] || false
  [[ "$ctx" == *"suggesting /clear"* ]] || false
  [[ "$ctx" == *"Every turn re-reads it."* ]] || false
  [[ "$ctx" != *"memory"* ]] || false
  [ "$(wc -w <<<"$ctx")" -le 60 ]
}

@test "silent at 199999 tokens" {
  run --separate-stderr nudge "$FIX/transcript_threshold_below.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "nudges at 200000 tokens, counting all three input terms" {
  run --separate-stderr nudge "$FIX/transcript_threshold_at.jsonl"
  [ "$status" -eq 0 ]
  [[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$output")" == "Context is 200k tokens."* ]] || false
}

@test "floors the token label" {
  run --separate-stderr nudge "$FIX/transcript_floor.jsonl"
  [ "$status" -eq 0 ]
  [[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$output")" == "Context is 249k tokens."* ]] || false
}

@test "silent after a compact boundary until the next response" {
  run --separate-stderr nudge "$FIX/transcript_compacted.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fails open on a jq runtime error" {
  printf '{"type":"assistant","message":{"usage":{"input_tokens":"x","cache_read_input_tokens":300000}}}\n' > "$BATS_TEST_TMPDIR/bad.jsonl"
  run --separate-stderr nudge "$BATS_TEST_TMPDIR/bad.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "reads only the tail of a big transcript" {
  big="$BATS_TEST_TMPDIR/big.jsonl"
  cat "$FIX/transcript_large.jsonl" > "$big"
  head -c 3000000 /dev/zero | tr '\0' 'x' >> "$big"
  run --separate-stderr nudge "$big"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "fails open on a missing transcript" {
  run --separate-stderr nudge "$BATS_TEST_TMPDIR/absent.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "fails open on a garbage transcript" {
  printf 'not json\n42\n{"type":"assistant","message":{"usage":"bad"}}\n' > "$BATS_TEST_TMPDIR/garbage.jsonl"
  run --separate-stderr nudge "$BATS_TEST_TMPDIR/garbage.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "fails open on garbage stdin" {
  run --separate-stderr bash "$HOOK" <<<'not json'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "nudges when the tail starts mid-line" {
  big="$BATS_TEST_TMPDIR/cut.jsonl"
  { printf '{"type":"user","message":{"content":"'; head -c 3000000 /dev/zero | tr '\0' x; printf '"}}\n'; cat "$FIX/transcript_large.jsonl"; } > "$big"
  run --separate-stderr nudge "$big"
  [ "$status" -eq 0 ]
  [[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$output")" == "Context is 369k tokens."* ]] || false
}

@test "nudges again after a compact boundary once a new response is big" {
  { cat "$FIX/transcript_compacted.jsonl"; sed -n 3p "$FIX/transcript_large.jsonl"; } > "$BATS_TEST_TMPDIR/recompacted.jsonl"
  run --separate-stderr nudge "$BATS_TEST_TMPDIR/recompacted.jsonl"
  [[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$output")" == "Context is 369k tokens."* ]] || false
}
