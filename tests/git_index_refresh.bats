#!/usr/bin/env bats
# Tests for git-index-refresh.zsh: a slow prompt starts one background
# `git status` that saves the index, which starship never does.
# shellcheck disable=SC2016 # single-quoted snippets are expanded by zsh, not bash

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # The user's global config signs commits and may set core.untrackedCache.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  T="$BATS_TEST_TMPDIR"
  R="$T/repo"
  git init -q "$R"
  echo a >"$R/a"
  git -C "$R" add a
  git -C "$R" -c user.name=t -c user.email=t@t commit -qm init
  mkdir -p "$T/bin"
  printf '#!/bin/sh\necho "$*" >>"%s/git.log"\nexec %s "$@"\n' "$T" "$(command -v git)" >"$T/bin/git"
  chmod +x "$T/bin/git"
}

# prompts <snippet>: runs <snippet> in the repo with the module loaded and the logging git first on PATH.
prompts() {
  zsh -f -c "cd '$R'; path=('$T/bin' \$path)
    source '$REPO_ROOT/private_dot_config/zsh/git-index-refresh.zsh'
    slow() { git_index_refresh_mark; (( git_index_refresh_start -= 0.5 )); git_index_refresh_maybe }
    fast() { git_index_refresh_mark; git_index_refresh_maybe }
    $1" 3>&-
}

# status_runs [expected]: waits up to 3s for <expected> runs, then a little more for an extra one.
status_runs() {
  local i n
  touch "$T/git.log"
  for i in $(seq 30); do
    n=$(grep -cw status "$T/git.log" || true)
    [ "${n:-0}" -ge "${1:-0}" ] && break
    sleep 0.1
  done
  sleep 0.2
  grep -cw status "$T/git.log" || true
}

has_untracked_cache() {
  local i
  for i in $(seq 30); do
    grep -qa UNTR "$R/.git/index" && return 0
    sleep 0.1
  done
  return 1
}

@test "git_index_refresh: a slow prompt saves the index with the untracked cache" {
  run grep -qa UNTR "$R/.git/index"
  [ "$status" -ne 0 ]
  prompts slow
  has_untracked_cache
}

@test "git_index_refresh: a fast prompt starts no git process" {
  prompts fast
  [ "$(status_runs)" -eq 0 ]
}

@test "git_index_refresh: a prompt without a mark starts no git process" {
  prompts git_index_refresh_maybe
  [ "$(status_runs)" -eq 0 ]
}

@test "git_index_refresh: typeahead starts no git process" {
  prompts 'PENDING=1; slow'
  [ "$(status_runs)" -eq 0 ]
}

@test "git_index_refresh: one job per slow streak, a fast prompt ends the streak" {
  prompts 'slow; slow; slow'
  [ "$(status_runs 1)" -eq 1 ]
  prompts 'slow; fast; slow'
  [ "$(status_runs 3)" -eq 3 ]
}

@test "git_index_refresh: a new directory starts a new job" {
  prompts 'slow; cd ..; slow'
  [ "$(status_runs 2)" -eq 2 ]
}

@test "git_index_refresh: keeps the repo's own core.untrackedCache" {
  git -C "$R" config core.untrackedCache false
  prompts slow
  [ "$(status_runs 1)" -eq 1 ]
  run grep -q untrackedCache=true "$T/git.log"
  [ "$status" -ne 0 ]
}

@test "git_index_refresh: registers its hooks when zle is on" {
  run zsh -fi -c "zmodload zsh/zle; source '$REPO_ROOT/private_dot_config/zsh/git-index-refresh.zsh'
    print -r -- \${precmd_functions[(r)git_index_refresh_mark]}
    zstyle -L zle-line-init" </dev/null
  echo "$output"
  [ "${lines[0]}" = git_index_refresh_mark ]
  [[ "${lines[1]}" == *git_index_refresh_maybe* ]]
}
