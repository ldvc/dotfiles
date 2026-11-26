#!/usr/bin/env bats
# Tests for mouse-reset.zsh: each prompt turns off mouse tracking that a dead TUI left on.
# shellcheck disable=SC2016 # single-quoted snippets are expanded by zsh, not bash

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "mouse_reset: prints the sequences that turn off every mouse mode" {
  run zsh -f -c "source '$REPO_ROOT/private_dot_config/zsh/mouse-reset.zsh'; mouse_reset"
  [ "$output" = $'\e[?1000l\e[?1002l\e[?1003l\e[?1006l' ]
}

@test "mouse_reset: registers a precmd hook when zle is on" {
  run zsh -fi -c "zmodload zsh/zle; source '$REPO_ROOT/private_dot_config/zsh/mouse-reset.zsh'
    print -r -- \${precmd_functions[(r)mouse_reset]}" </dev/null
  [ "$output" = mouse_reset ]
}
