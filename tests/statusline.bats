#!/usr/bin/env bats
# Tests for dot_claude/statusline-command.sh: absolute context tokens, colored by fixed thresholds.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/dot_claude/statusline-command.sh"
}

# status_line <tokens> [used_percentage] [window]
status_line() {
  printf '{"model":{"display_name":"Opus 5.5"},"context_window":{"total_input_tokens":%s,"context_window_size":%s,"used_percentage":%s}}' \
    "$1" "${3:-1000000}" "${2:-31}" | bash "$SCRIPT"
}

dim=$'\e[2m'
green=$'\e[2;32m'
yellow=$'\e[2;33m'
red=$'\e[31m'

@test "green below 150k, floored to k" {
  run status_line 149999 14
  [ "$status" -eq 0 ]
  [[ "$output" == *"Opus 5.5"* ]] || false
  [[ "$output" == *"${green}149k"* ]] || false
  [[ "$output" != *"/clear"* ]] || false
}

@test "yellow from 150k up to 299999" {
  run status_line 150000
  [[ "$output" == *"${yellow}150k"* ]] || false
  run status_line 299999
  [[ "$output" == *"${yellow}299k"* ]] || false
  [[ "$output" != *"/clear"* ]] || false
}

@test "red with a /clear hint from 300k" {
  run status_line 300000
  [[ "$output" == *"${red}300k /clear?"* ]] || false
}

@test "red with a /clear hint from 80% of a small window" {
  run status_line 170000 85 200000
  [[ "$output" == *"${red}170k /clear?"* ]] || false
}

@test "80% is the red boundary" {
  run status_line 100000 80
  [[ "$output" == *"${red}100k /clear?"* ]] || false
  run status_line 100000 79
  [[ "$output" == *"${green}100k"* ]] || false
  [[ "$output" != *"/clear"* ]] || false
}

@test "appends the dimmed percentage" {
  run status_line 369101 37
  [[ "$output" == *"${dim}37%"* ]] || false
}

@test "zero before the first API response, no percentage" {
  run bash "$SCRIPT" <<<'{"model":{"display_name":"Opus 5.5"},"context_window":{"total_input_tokens":0,"used_percentage":null,"current_usage":null}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"${green}0k"* ]] || false
  [[ "$output" != *"%"* ]] || false
}

@test "missing context_window shows 0k" {
  run bash "$SCRIPT" <<<'{"model":{"display_name":"Opus 5.5"}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"${green}0k"* ]] || false
}
