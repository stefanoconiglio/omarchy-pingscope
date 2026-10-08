#!/bin/bash

# PingScope's terminal: one shell running `ping <host> -i 1`, kept in a tmux
# session of its own (server `pingscope`), so the ping goes on whether anyone
# looks or not. Hovering the bar face shows that session's screen; a click
# attaches a terminal to it, which the widget closes when it loses focus.
#
#   ping-terminal.sh session <host>                   start the session unless it runs
#   ping-terminal.sh attach <host> <x> <y> <w> <h>    a terminal attached to it, floating
#                                                     at x,y (monitor-local), w×h
#
# The session's shell reads this same file as its rcfile (bash --rcfile).

if [[ $- == *i* ]]; then
  [[ -f ~/.bashrc ]] && source ~/.bashrc

  # Type the command at the prompt: ask the terminal for its status (CSI 5 n);
  # its answer (CSI 0 n) comes back as input, which readline expands into the
  # command and Enter. Echo stays off until the first prompt, so the answer is
  # never printed as ^[[0n before readline reads it. Ctrl+C stops the ping and
  # leaves the shell; Up brings the command back to change it.
  bind "\"\\e[0n\": \"ping ${PINGSCOPE_HOST} -i 1\\C-m\""
  unset PINGSCOPE_HOST
  __pingscope_echo() {
    stty echo
    PROMPT_COMMAND=${PROMPT_COMMAND/__pingscope_echo;/}
    unset -f __pingscope_echo
  }
  PROMPT_COMMAND="__pingscope_echo;${PROMPT_COMMAND}"
  stty -echo
  printf '\e[5n'
  return
fi

SERVER=pingscope
SESSION=ping
APP_ID=pingscope.terminal
self=$(realpath "$0")
conf="${self%/*}/tmux.conf"

usage() {
  echo "usage: ${0##*/} session <host> | attach <host> <x> <y> <width> <height>" >&2
  exit 2
}

session_tmux() {
  tmux -L "$SERVER" -f "$conf" "$@"
}

start_session() {
  session_tmux has-session -t "=$SESSION" 2>/dev/null && return 0
  cd ~ || true
  # One bar per monitor may start it at once: losing that race is fine.
  session_tmux new-session -d -s "$SESSION" -x 94 -y 17 -e "PINGSCOPE_HOST=$1" \
    bash --rcfile "$self" -i 2>/dev/null ||
    session_tmux has-session -t "=$SESSION" 2>/dev/null
}

# Only hostnames and addresses: the host ends up inside a readline macro.
[[ ${2:-} =~ ^[A-Za-z0-9][A-Za-z0-9.:-]*$ ]] || usage

case $1 in
  session)
    start_session "$2"
    ;;
  attach)
    (( $# == 6 )) || usage
    for n in "$3" "$4" "$5" "$6"; do [[ $n =~ ^[0-9]+$ ]] || usage; done
    start_session "$2" || exit 1
    # Where the hover view was, so the terminal takes its place. The rule from
    # the last attach is replaced, so attaches never pile rules up.
    printf -v rule 'if pingscope_terminal_rule then pingscope_terminal_rule:set_enabled(false) end; pingscope_terminal_rule = hl.window_rule({ match = { class = "^pingscope\\\\.terminal$" }, float = true, move = { %d, %d }, size = { %d, %d } })' "$3" "$4" "$5" "$6"
    hyprctl eval "$rule" >/dev/null 2>&1
    exec omarchy-launch-tui --app-id="$APP_ID" tmux -L "$SERVER" -f "$conf" attach-session -t "=$SESSION"
    ;;
  *)
    usage
    ;;
esac
