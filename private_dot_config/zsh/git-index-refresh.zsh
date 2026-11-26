# Starship's git (GIT_OPTIONAL_LOCKS=0) never saves the index: a slow prompt starts one background git status to save it.
# 100ms: a fresh 24k-file repo renders in about 65ms, a stale one in 300ms or more.
zmodload zsh/datetime

git_index_refresh_mark() { git_index_refresh_start=$EPOCHREALTIME }

git_index_refresh_maybe() {
  emulate -L zsh
  (( ${+git_index_refresh_start} )) || return 0
  local ms=$(( (EPOCHREALTIME - git_index_refresh_start) * 1000 ))
  unset git_index_refresh_start
  if (( ms <= 100 )); then
    unset git_index_refresh_dir
    return 0
  fi
  # One job per slow streak: a repo that stays slow must not take index.lock after every prompt.
  # shortcut: a failed job is not retried until cd or a fast prompt, add a time-based retry if this bites.
  [[ $PWD != ${git_index_refresh_dir-} ]] || return 0
  # PENDING > 0 means typeahead: a queued git command would meet our index.lock.
  (( ${PENDING:-0} == 0 )) || return 0
  git_index_refresh_dir=$PWD
  {
    local -a uc
    command git config core.untrackedCache >/dev/null || uc=(-c core.untrackedCache=true)
    command git $uc status --porcelain --no-renames --ignore-submodules=all
  } </dev/null >/dev/null 2>&1 &!
}

if [[ -o zle ]]; then
  autoload -Uz add-zsh-hook add-zle-hook-widget
  add-zsh-hook precmd git_index_refresh_mark
  add-zle-hook-widget line-init git_index_refresh_maybe
fi
