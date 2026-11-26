# One ssh-agent per user on a fixed socket. A live foreign socket (launchd, forwarded) is kept
# without a fork; only the fixed one is probed, since a dead agent leaves its file behind.
() {
  local fixed=$HOME/.ssh-agent/ssh-agent.sock rc fd
  [[ -S $SSH_AUTH_SOCK && $SSH_AUTH_SOCK != $fixed ]] && return
  export SSH_AUTH_SOCK=$fixed
  unset SSH_AGENT_PID
  ssh-add -l >/dev/null 2>&1; rc=$?
  if (( rc == 2 )); then
    mkdir -p -m 700 ${fixed:h} && [[ -O ${fixed:h} ]] || return
    # Shells restored together would each start an agent and orphan all but one.
    zmodload -F zsh/system b:zsystem
    : >>${fixed:h}/lock
    zsystem flock -t 5 -f fd ${fixed:h}/lock || return
    ssh-add -l >/dev/null 2>&1; rc=$?
    if (( rc == 2 )); then
      rm -f $fixed
      ssh-agent -a $fixed >/dev/null && rc=1
    fi
    zsystem flock -u $fd
  fi
  # Not only after a start: a tty-less first shell cannot prompt for the passphrase.
  (( rc == 1 )) && [[ -t 0 ]] && ssh-add ~/.ssh/id_ed25519 2>/dev/null
}
