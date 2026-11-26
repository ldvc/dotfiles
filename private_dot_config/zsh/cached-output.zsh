# Caches `tool init`-style output so startup skips a fork. The stamp holds the
# resolved binary, since a brew upgrade installs one with its old build mtime.
cached_output() {
  local bin=$commands[$1] dir=${XDG_CACHE_HOME:-$HOME/.cache} cache stamp line out tmp
  [[ -n $bin ]] || return 1
  [[ $dir == /* ]] || dir=$HOME/.cache
  cache=$dir/zsh/$1.zsh
  stamp="# ${bin:A}${2+ ${(j: :)${(q)@[2,-1]}}}"
  [[ -O ${cache:h} && -O $cache ]] && { IFS= read -r line <$cache } 2>/dev/null
  if [[ $line != "$stamp" || $bin -nt $cache ]]; then
    out=$("$bin" "${@:2}") && [[ -n $out ]] || return 1
    mkdir -p ${cache:h} && [[ -O ${cache:h} ]] || return 1
    tmp=$(mktemp $cache.XXXXXX) || return 1
    print -r -- "$stamp"$'\n'"$out" >|$tmp && mv -f $tmp $cache || { rm -f $tmp; return 1 }
  fi
  REPLY=$cache
}
