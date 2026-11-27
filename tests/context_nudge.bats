#!/usr/bin/env bats
# Tests for dot_claude/hooks/context-nudge.sh: UserPromptSubmit nudge to /clear past 120k tokens or after a task-boundary command.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$REPO_ROOT/dot_claude/hooks/context-nudge.sh"
  FIX="$BATS_TEST_DIRNAME/fixtures"
}

nudge() {
  printf '{"hook_event_name":"UserPromptSubmit","transcript_path":"%s"}' "$1" | bash "$HOOK"
}

context_of() {
  jq -r .hookSpecificOutput.additionalContext <<<"$output"
}

@test "silent below 120k, ignoring a larger sidechain turn" {
  run --separate-stderr nudge "$FIX/transcript_small.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "emits UserPromptSubmit additionalContext from the last main-chain turn" {
  run --separate-stderr nudge "$FIX/transcript_large.jsonl"
  [ "$status" -eq 0 ]
  [ "$(jq -r .hookSpecificOutput.hookEventName <<<"$output")" = "UserPromptSubmit" ]
  ctx="$(context_of)"
  [[ "$ctx" == "Context is 369k tokens."* ]] || false
  [[ "$ctx" == *"suggesting /clear"* ]] || false
  [[ "$ctx" == *"Every turn re-reads it."* ]] || false
  [[ "$ctx" != *"memory"* ]] || false
  [ "$(wc -w <<<"$ctx")" -le 60 ]
}

@test "silent at 119999 tokens" {
  run --separate-stderr nudge "$FIX/transcript_threshold_below.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "nudges at 120000 tokens, counting all three input terms" {
  run --separate-stderr nudge "$FIX/transcript_threshold_at.jsonl"
  [ "$status" -eq 0 ]
  [[ "$(context_of)" == "Context is 120k tokens."* ]] || false
}

@test "floors the token label" {
  run --separate-stderr nudge "$FIX/transcript_floor.jsonl"
  [ "$status" -eq 0 ]
  [[ "$(context_of)" == "Context is 249k tokens."* ]] || false
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
  [[ "$(context_of)" == "Context is 369k tokens."* ]] || false
}

@test "nudges again after a compact boundary once a new response is big" {
  { cat "$FIX/transcript_compacted.jsonl"; sed -n 3p "$FIX/transcript_large.jsonl"; } > "$BATS_TEST_TMPDIR/recompacted.jsonl"
  run --separate-stderr nudge "$BATS_TEST_TMPDIR/recompacted.jsonl"
  [[ "$(context_of)" == "Context is 369k tokens."* ]] || false
}

@test "nudges below 120k when the last turn ran git push" {
  run --separate-stderr nudge "$FIX/transcript_push.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(jq -r .hookSpecificOutput.hookEventName <<<"$output")" = "UserPromptSubmit" ]
  ctx="$(context_of)"
  [[ "$ctx" == "The previous turn ran git push or posted a Jira comment"* ]] || false
  [[ "$ctx" == *"Context is 51k tokens."* ]] || false
  [[ "$ctx" == *"suggesting /clear"* ]] || false
  [ "$(wc -w <<<"$ctx")" -le 60 ]
}

@test "nudges when the last turn posted a Jira comment" {
  sed 's/git push origin main/jira issue comment add ABC-1 done/' "$FIX/transcript_push.jsonl" > "$BATS_TEST_TMPDIR/t.jsonl"
  run --separate-stderr nudge "$BATS_TEST_TMPDIR/t.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$(context_of)" == "The previous turn ran git push"* ]] || false
}

@test "nudges on git -C <dir> push" {
  sed 's|git push origin main|cd /y \&\& git -C /x push -u origin feat|' "$FIX/transcript_push.jsonl" > "$BATS_TEST_TMPDIR/t.jsonl"
  run --separate-stderr nudge "$BATS_TEST_TMPDIR/t.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$(context_of)" == "The previous turn ran git push"* ]] || false
}

@test "a task notification and its reply keep the boundary flag" {
  { cat "$FIX/transcript_push.jsonl"
    printf '{"type":"user","isMeta":null,"isSidechain":false,"origin":{"kind":"task-notification"},"message":{"role":"user","content":"<task-notification>\\n<task-id>b1</task-id>"}}\n'
    sed -n 4p "$FIX/transcript_push.jsonl"; } > "$BATS_TEST_TMPDIR/t.jsonl"
  run --separate-stderr nudge "$BATS_TEST_TMPDIR/t.jsonl"
  [ "$status" -eq 0 ]
  [[ "$(context_of)" == "The previous turn ran git push"* ]] || false
}

@test "silent on look-alike commands" {
  sed 's/git push origin main/git pushx; git log --grep push; ajira issue comment add/' "$FIX/transcript_push.jsonl" > "$BATS_TEST_TMPDIR/t.jsonl"
  run --separate-stderr nudge "$BATS_TEST_TMPDIR/t.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "still nudges when the new prompt is already in the transcript" {
  { cat "$FIX/transcript_push.jsonl"; printf '{"type":"user","isSidechain":false,"message":{"role":"user","content":"next"}}\n'; } > "$BATS_TEST_TMPDIR/t.jsonl"
  run --separate-stderr nudge "$BATS_TEST_TMPDIR/t.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$(context_of)" == "The previous turn ran git push"* ]] || false
}

@test "silent when the push was in an earlier turn" {
  { cat "$FIX/transcript_push.jsonl"
    printf '{"type":"user","isSidechain":false,"message":{"role":"user","content":"next"}}\n'
    sed -n 4p "$FIX/transcript_push.jsonl"; } > "$BATS_TEST_TMPDIR/t.jsonl"
  run --separate-stderr nudge "$BATS_TEST_TMPDIR/t.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent when only a sidechain ran git push" {
  sed '2s/"isSidechain":false/"isSidechain":true/' "$FIX/transcript_push.jsonl" > "$BATS_TEST_TMPDIR/t.jsonl"
  run --separate-stderr nudge "$BATS_TEST_TMPDIR/t.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent when a non-Bash tool input has a git push command" {
  sed 's/"name":"Bash"/"name":"Monitor"/' "$FIX/transcript_push.jsonl" > "$BATS_TEST_TMPDIR/t.jsonl"
  run --separate-stderr nudge "$BATS_TEST_TMPDIR/t.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a meta user entry and a tool_result inside the push turn keep the flag" {
  { sed -n 1,3p "$FIX/transcript_push.jsonl"
    printf '{"type":"user","isMeta":true,"isSidechain":false,"message":{"role":"user","content":"caveat"}}\n'
    sed -n 4p "$FIX/transcript_push.jsonl"; } > "$BATS_TEST_TMPDIR/t.jsonl"
  run --separate-stderr nudge "$BATS_TEST_TMPDIR/t.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$(context_of)" == "The previous turn ran git push"* ]] || false
}

@test "a compact boundary drops the boundary flag" {
  { cat "$FIX/transcript_push.jsonl"; printf '{"type":"system","subtype":"compact_boundary","isSidechain":false}\n'; } > "$BATS_TEST_TMPDIR/t.jsonl"
  run --separate-stderr nudge "$BATS_TEST_TMPDIR/t.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "over the threshold with a push, emits the threshold message once" {
  { cat "$FIX/transcript_push.jsonl"; sed -n 3p "$FIX/transcript_large.jsonl"; } > "$BATS_TEST_TMPDIR/t.jsonl"
  run --separate-stderr nudge "$BATS_TEST_TMPDIR/t.jsonl"
  [ "$(jq -s length <<<"$output")" -eq 1 ]
  [[ "$(context_of)" == "Context is 369k tokens. Every turn re-reads it."* ]] || false
}

@test "a non-object origin does not drop the threshold nudge" {
  { cat "$FIX/transcript_large.jsonl"; printf '{"type":"user","isSidechain":false,"origin":"weird","message":{"content":"x"}}\n'; } > "$BATS_TEST_TMPDIR/origin.jsonl"
  run --separate-stderr nudge "$BATS_TEST_TMPDIR/origin.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$(context_of)" == "Context is 369k tokens."* ]] || false
}

@test "a non-object tool_use input does not drop the threshold nudge" {
  { cat "$FIX/transcript_large.jsonl"
    printf '{"type":"assistant","isSidechain":false,"message":{"content":[{"type":"tool_use","name":"Bash","input":"str"}],"usage":{"input_tokens":1,"cache_read_input_tokens":200000,"cache_creation_input_tokens":1}}}\n'; } > "$BATS_TEST_TMPDIR/t.jsonl"
  run --separate-stderr nudge "$BATS_TEST_TMPDIR/t.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$(context_of)" == "Context is 200k tokens."* ]] || false
}
