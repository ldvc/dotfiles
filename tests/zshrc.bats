#!/usr/bin/env bats
# Tests for dot_zshrc: an interactive startup picks the Homebrew prefix and prints nothing on stderr.
# shellcheck disable=SC2016 # single-quoted snippets are expanded by zsh, not bash

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # ssh-agent.zsh binds a socket under HOME; Unix socket paths max out near 104 bytes and BATS_TEST_TMPDIR is too deep.
  H="$(mktemp -d "${TMPDIR:-/tmp}/zr.XXXXXX")"
  mkdir -p "$H/.config/zsh"
  cp "$REPO_ROOT/dot_zshrc" "$H/.zshrc"
  cp "$REPO_ROOT"/private_dot_config/zsh/*.zsh "$H/.config/zsh/"
}

teardown() {
  pkill -f "ssh-agent -a $H/" || true
  rm -rf "$H"
}

start_shell() {
  env -u HOMEBREW_PREFIX -u HOMEBREW_CASK_OPTS -u XDG_CONFIG_HOME -u XDG_CACHE_HOME -u SSH_AUTH_SOCK \
    HOME="$H" ZDOTDIR="$H" zsh -i -c 'print -r -- "prefix=$HOMEBREW_PREFIX"
      print -r -- "path1=$path[1]"
      print -r -- "cask=${HOMEBREW_CASK_OPTS-<unset>}"' </dev/null
}

@test "zshrc: with ~/.pkg/bin, uses the ~/.pkg prefix and sets the cask folder" {
  mkdir -p "$H/.pkg/bin"
  run --separate-stderr start_shell
  echo "$output" "$stderr"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "prefix=$H/.pkg" ]
  [ "${lines[1]}" = "path1=$H/.pkg/bin" ]
  [ "${lines[2]}" = "cask=--appdir=~/Applications" ]
  [ -z "$stderr" ]
}

@test "zshrc: without ~/.pkg/bin, uses /opt/homebrew and leaves the cask folder unset" {
  run --separate-stderr start_shell
  echo "$output" "$stderr"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "prefix=/opt/homebrew" ]
  [ "${lines[1]}" = "path1=/opt/homebrew/bin" ]
  [ "${lines[2]}" = "cask=<unset>" ]
  [ -z "$stderr" ]
}
