# A TUI that dies with mouse tracking on makes the terminal type "35;17;21M" into the prompt at each mouse move.
# Each prompt turns it off: a TUI turns it back on when it starts.
mouse_reset() { print -n '\e[?1000l\e[?1002l\e[?1003l\e[?1006l' }

if [[ -o zle ]]; then
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd mouse_reset
fi
