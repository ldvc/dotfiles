# difft — set $DFT_BACKGROUND so difftastic picks the right palette
# for the terminal's current light/dark appearance.
#
# difftastic reads $DFT_BACKGROUND (values: "light" or "dark") to choose its
# color scheme. Exporting it once per shell would go stale the moment macOS
# (or the terminal) toggles appearance, so we re-detect just-in-time, in front
# of the commands that actually render a diff.
#
# Detection order (first hit wins):
#   1) CSI ?996n appearance query — only attempted in Ghostty outside tmux,
#      since the sequence isn't proxied through tmux and other terminals may
#      not answer (causing the read to time out).
#         Reply: ESC [ ? 997 ; 1 n  → dark
#                ESC [ ? 997 ; 2 n  → light
#   2) macOS `defaults read -g AppleInterfaceStyle` — set to "Dark" when dark
#      mode is active, missing key (non-zero exit) when light.
#
# Skipped entirely on non-interactive shells (no tty on stdin/stdout) so that
# scripts, CI, and redirected pipelines don't hang on the escape-sequence read.
#
# Wrappers:
#   difft …         → refresh DFT_BACKGROUND, then run difft.
#   git diff|show|log|difftool|dl|ds|dft …
#                   → refresh DFT_BACKGROUND, then run git. The matched git
#                     aliases (dl/ds/dft) are the ones configured in
#                     ~/.gitconfig that actually drive difftastic via
#                     `-c diff.external=difft`. Other git subcommands fall
#                     through with no extra cost beyond a case match.

__dft_bg() {
  # Skip the query entirely if we're not on an interactive tty —
  # avoids hangs in scripts, CI, or when stdin is redirected.
  [[ -t 0 && -t 1 ]] || return

  local response=""

  # Only try the escape-sequence query in terminals likely to support it.
  # TERM_PROGRAM is set by Ghostty (and most modern terminals).
  # Inside tmux, $TMUX is set and the query won't be proxied — skip it.
  if [[ -z "$TMUX" && "$TERM_PROGRAM" == "ghostty" ]]; then
    # Save terminal state, query, read reply with a tight timeout.
    # Reply format: ESC [ ? 997 ; 1 n  (dark)  or  ESC [ ? 997 ; 2 n  (light)
    printf '\e[?996n'
    read -rs -t 0.1 -d 'n' response 2>/dev/null
  fi

  if [[ "$response" == *"997;1"* ]]; then
    export DFT_BACKGROUND=dark
  elif [[ "$response" == *"997;2"* ]]; then
    export DFT_BACKGROUND=light
  else
    # Fallback: ask macOS directly.
    if defaults read -g AppleInterfaceStyle &>/dev/null; then
      export DFT_BACKGROUND=dark
    else
      export DFT_BACKGROUND=light
    fi
  fi
}

# Surgical wrappers — only pay the cost when actually diffing.
difft() { __dft_bg; command difft "$@" }

git() {
  case "$1" in
    diff|show|log|difftool|dl|ds|dft)
      __dft_bg
      ;;
  esac
  command git "$@"
}
