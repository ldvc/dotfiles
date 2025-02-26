# Unset the default fish greeting text which messes up Zellij
set fish_greeting

set -x ZELLIJ_AUTO_EXIT true
if status is-interactive
    # Commands to run in interactive sessions can go here
    # At this point, specify the Zellij config dir, so we can launch it manually if we want to
    export ZELLIJ_CONFIG_DIR=$HOME/.config/zellij

    # Check if our Terminal emulator is Ghostty
    if [ "$TERM" = xterm-ghostty ]
        # Launch zellij
        #eval (zellij setup --generate-auto-start fish | string collect)
    end
end

set -g theme_nerd_fonts yes
set -g theme_display_date no
set -g theme_color_scheme catppuccin-mocha
set -g theme_display_git_untracked no
set -g theme_display_git_dirty yes

alias vim nvim
alias k kubectl
