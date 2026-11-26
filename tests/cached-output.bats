#!/usr/bin/env bats
# Tests for cached_output: the startup cache for `tool init`-style scripts.
# shellcheck disable=SC2016 # single-quoted snippets are expanded by zsh, not bash

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  unset XDG_CACHE_HOME
  T="$BATS_TEST_TMPDIR"
  mkdir -p "$T/bin" "$T/v1" "$T/v2" "$T/home"
  for v in v1 v2; do
    printf '#!/bin/sh\necho x >>"%s/runs"\necho "print -r -- %s:$*"\n' "$T" "$v" >"$T/$v/tool"
    chmod +x "$T/$v/tool"
  done
  ln -s "$T/v1/tool" "$T/bin/tool"
}

# load_tool [args...]: prints what sourcing the cached output of `tool args`
# (default: init zsh) printed. HOME is a scratch dir: the default cache lives there.
load_tool() {
  (($#)) || set -- init zsh
  HOME="$T/home" XDG_CACHE_HOME="${XDG_CACHE_HOME-$T/cache}" zsh -f -c "path=('$T/bin' \$path)
    source '$REPO_ROOT/private_dot_config/zsh/cached-output.zsh'
    cached_output tool \"\$@\" && source \$REPLY" zsh "$@"
}

runs() {
  wc -l <"$T/runs" | tr -d ' '
}

@test "cached_output: runs the tool once, then sources the cache" {
  run load_tool
  [ "$output" = "v1:init zsh" ]
  run load_tool
  [ "$output" = "v1:init zsh" ]
  [ "$(runs)" -eq 1 ]
  [ -s "$T/cache/zsh/tool.zsh" ]
}

@test "cached_output: reruns when the binary is newer than the cache" {
  load_tool
  touch -t 203001010000 "$T/v1/tool"
  run load_tool
  [ "$output" = "v1:init zsh" ]
  [ "$(runs)" -eq 2 ]
}

@test "cached_output: reruns when the command resolves to another, older file" {
  load_tool
  touch -t 200001010000 "$T/v2/tool"
  ln -sfn "$T/v2/tool" "$T/bin/tool"
  run load_tool
  [ "$output" = "v2:init zsh" ]
}

@test "cached_output: reruns when the arguments change" {
  load_tool multi a
  run load_tool multi b
  [ "$output" = "v1:multi b" ]
}

@test "cached_output: reruns when the arguments after an empty first one change" {
  load_tool "" a
  run load_tool "" b
  [ "$output" = "v1: b" ]
}

@test "cached_output: runs the binary, not a shell function of the same name" {
  run zsh -f -c "path=('$T/bin' \$path); tool() { print -r -- 'print -r -- function' }
    source '$REPO_ROOT/private_dot_config/zsh/cached-output.zsh'
    XDG_CACHE_HOME='$T/cache' cached_output tool init zsh && source \$REPLY"
  [ "$output" = "v1:init zsh" ]
}

@test "cached_output: fails and caches nothing for a missing command or empty output" {
  run zsh -f -c "source '$REPO_ROOT/private_dot_config/zsh/cached-output.zsh'; cached_output no-such-tool-xyz"
  [ "$status" -eq 1 ]
  printf '#!/bin/sh\n' >"$T/v1/tool"
  run load_tool
  [ "$status" -eq 1 ]
  [ ! -e "$T/cache/zsh/tool.zsh" ]
}

@test "cached_output: fails and caches nothing when the command fails" {
  printf '#!/bin/sh\necho "print -r -- partial"\nexit 1\n' >"$T/v1/tool"
  run load_tool
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ ! -e "$T/cache/zsh/tool.zsh" ]
}

@test "cached_output: fails once the command is gone, even with a cache" {
  load_tool
  rm "$T/bin/tool"
  run load_tool
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "cached_output: ignores a relative XDG_CACHE_HOME" {
  local stamp
  stamp="# $(zsh -f -c 'print -r -- ${1:A}' zsh "$T/v1/tool") init zsh"
  mkdir -p "$T/rel/zsh"
  printf '%s\nprint -r -- planted\n' "$stamp" >"$T/rel/zsh/tool.zsh"
  cd "$T"
  XDG_CACHE_HOME=rel run load_tool
  [ "$output" = "v1:init zsh" ]
  [ -s "$T/home/.cache/zsh/tool.zsh" ]
}

@test "cached_output: caches a call with no arguments" {
  local no_args='path=("$1" $path); source "$2"; cached_output tool && source $REPLY'
  HOME="$T/home" XDG_CACHE_HOME="$T/cache" zsh -f -c "$no_args" zsh "$T/bin" "$REPO_ROOT/private_dot_config/zsh/cached-output.zsh"
  HOME="$T/home" XDG_CACHE_HOME="$T/cache" zsh -f -c "$no_args" zsh "$T/bin" "$REPO_ROOT/private_dot_config/zsh/cached-output.zsh"
  [ "$(runs)" -eq 1 ]
}
