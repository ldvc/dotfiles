# k9s hard-codes its flash and log colors as palette indices, and Ghostty's Alabaster values for them are unreadable on #f7f7f7.
# The palette changes only while k9s runs, so other apps keep the theme colors.
k9s() {
  if [[ $TERM_PROGRAM == ghostty && $(defaults read -g AppleInterfaceStyle 2>/dev/null) != Dark ]]; then
    print -n '\e]4;2;#3d7e23;10;#3d7e23;14;#0078a3;202;#aa3731;214;#936800;223;#6f6f6f\a'
  fi
  { command k9s "$@" } always { print -n '\e]104\a' }
}
