#!/usr/bin/env bats
# Claude Code's shell snapshot drops every function named "_x" (the zsh
# completion convention; "__x" survives), so a wrapper calling one fails in the Bash tool.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "no zsh function name starts with a single underscore" {
  run grep -nE '^[[:space:]]*(function[[:space:]]+)?_[A-Za-z0-9][A-Za-z0-9_]*[[:space:]]*(\(\)|\{)' \
    "$REPO_ROOT"/private_dot_config/zsh/*.zsh "$REPO_ROOT"/dot_zshrc
  echo "$output"
  [ "$status" -eq 1 ]
}
