#!/usr/bin/env bats
# Tests for ssh-agent.zsh: one agent per user on a fixed socket, not one per shell.
# shellcheck disable=SC2016 # single-quoted snippets are expanded by zsh, not bash
# shellcheck disable=SC2030,SC2031 # each test sets SSH_AUTH_SOCK for itself only

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  unset SSH_AUTH_SOCK SSH_AGENT_PID
  # Unix socket paths max out near 104 bytes; BATS_TEST_TMPDIR is too deep.
  H="$(mktemp -d "${TMPDIR:-/tmp}/sa.XXXXXX")"
  FIXED="$H/.ssh-agent/ssh-agent.sock"
}

teardown() {
  pkill -f "ssh-agent -a $H/" || true
  rm -rf "$H"
}

# snippet [prelude]: zsh code that sources the module like a fresh interactive
# shell, then prints the agent socket and `ssh-add -l`'s exit code
# (0: holds a key, 1: live and empty, 2: unreachable).
snippet() {
  printf '%s\n' "$1" "source '$REPO_ROOT/private_dot_config/zsh/ssh-agent.zsh'" \
    'print -r -- $SSH_AUTH_SOCK' 'command ssh-add -l >/dev/null 2>&1; print rc=$?'
}

# stdin from /dev/null: under `make test` in a terminal it would be a tty.
new_shell() {
  HOME="$H" zsh -f -c "$(snippet "${1-}")" </dev/null
}

# new_tty_shell: same, with stdin on a pty. util-linux script hands its command
# to $SHELL -c; a file avoids a second quoting layer. BSD script echoes "^D\b\b" first.
new_tty_shell() {
  snippet "${1-}" >"$H/s.zsh"
  if script --version >/dev/null 2>&1; then
    HOME="$H" script -qec "zsh -f $H/s.zsh" /dev/null </dev/null
  else
    HOME="$H" script -q /dev/null zsh -f "$H/s.zsh" </dev/null
  fi | tr -d '\r\b' | sed 's/^\^D//'
}

agents() {
  pgrep -f "ssh-agent -a $H/" | wc -l | tr -d ' '
}

add_key() {
  mkdir -p "$H/.ssh"
  ssh-keygen -q -t ed25519 -N '' -f "$H/.ssh/id_ed25519"
}

@test "ssh-agent: without an agent, starts one on the fixed socket" {
  run new_shell
  [ "${lines[0]}" = "$FIXED" ]
  [ "${lines[1]}" = "rc=1" ]
  [ "$(agents)" -eq 1 ]
}

@test "ssh-agent: later shells reuse the running agent" {
  new_shell
  run new_shell
  [ "${lines[0]}" = "$FIXED" ]
  [ "${lines[1]}" = "rc=1" ]
  run new_shell
  [ "$(agents)" -eq 1 ]
}

@test "ssh-agent: shells starting together leave one agent" {
  # Staggered rm makes a lock-less module delete a socket another shell already bound.
  for i in 1 2 3 4 5 6 7 8; do new_shell "rm() { sleep 0.$i; command rm \"\$@\" }" >/dev/null & done
  wait
  [ "$(agents)" -eq 1 ]
}

@test "ssh-agent: replaces a stale socket left by a dead agent" {
  mkdir -p "${FIXED%/*}"
  perl -MIO::Socket::UNIX -e 'IO::Socket::UNIX->new(Local => shift, Listen => 1) or die "$!\n"' "$FIXED"
  [ -S "$FIXED" ]
  run new_shell
  [ "${lines[0]}" = "$FIXED" ]
  [ "${lines[1]}" = "rc=1" ]
  [ "$(agents)" -eq 1 ]
}

@test "ssh-agent: SSH_AUTH_SOCK already on the fixed path with no agent starts one" {
  export SSH_AUTH_SOCK="$FIXED"
  run new_shell
  [ "${lines[0]}" = "$FIXED" ]
  [ "${lines[1]}" = "rc=1" ]
  [ "$(agents)" -eq 1 ]
}

@test "ssh-agent: SSH_AUTH_SOCK on a missing path falls back to the fixed socket" {
  export SSH_AUTH_SOCK="$H/gone.sock"
  run new_shell
  [ "${lines[0]}" = "$FIXED" ]
  [ "${lines[1]}" = "rc=1" ]
  [ "$(agents)" -eq 1 ]
}

@test "ssh-agent: keeps a live agent from elsewhere without running ssh-add or ssh-agent" {
  ssh-agent -a "$H/other.sock" >/dev/null
  export SSH_AUTH_SOCK="$H/other.sock"
  run new_shell 'ssh-add() { print x >>$HOME/calls }; ssh-agent() { print x >>$HOME/calls }'
  [ "${lines[0]}" = "$H/other.sock" ]
  [ "${lines[1]}" = "rc=1" ]
  [ ! -e "$H/calls" ]
  [ ! -e "$FIXED" ]
  [ "$(agents)" -eq 1 ]
}

@test "ssh-agent: with a tty, adds the key to a new agent" {
  add_key
  run new_tty_shell
  [ "${lines[0]}" = "$FIXED" ]
  [ "${lines[1]}" = "rc=0" ]
}

@test "ssh-agent: without a tty, leaves the agent empty" {
  add_key
  run new_shell
  [ "${lines[1]}" = "rc=1" ]
}

@test "ssh-agent: with a tty, adds the key to an agent a tty-less shell left empty" {
  add_key
  new_shell
  run new_tty_shell
  [ "${lines[1]}" = "rc=0" ]
  [ "$(agents)" -eq 1 ]
}

@test "ssh-agent: with a tty, does not add the key again to an agent that holds one" {
  add_key
  new_tty_shell
  run new_tty_shell 'ssh-add() { [[ $1 == -l ]] || print x >>$HOME/calls; command ssh-add "$@" }'
  [ "${lines[1]}" = "rc=0" ]
  [ ! -e "$H/calls" ]
}
