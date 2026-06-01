#!/bin/bash
# =============================================================
# iyf-show-alert — canonical full-screen alert launcher
# -------------------------------------------------------------
# The browser-launching half of "In Your Face", factored out so
# both entry points share one implementation and can't drift:
#   - iyf.sh             (zsh preexec/precmd terminal hook)
#   - iyf-claude-hook.sh (Claude Code Stop hook)
#
# Usage: iyf-show-alert.sh <label> <formatted-duration> <exit-code>
# Reads from the environment:
#   IYF_ALERT_FILE  path to alert.html        (default ~/.iyf/alert.html)
#   IYF_AUTO_CLOSE  seconds before auto-close (default 90)
# =============================================================
set -u

cmd=${1:-}
duration=${2:-}
code=${3:-0}

alert_file=${IYF_ALERT_FILE:-$HOME/.iyf/alert.html}
auto_close=${IYF_AUTO_CLOSE:-90}

# URL-encode the label so query parsing in alert.html stays intact; degrade to
# the raw string if python3 isn't around.
encoded_cmd=$(printf '%s' "$cmd" \
  | python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read().strip()))" 2>/dev/null \
  || printf '%s' "$cmd")

url="file://${alert_file}?cmd=${encoded_cmd}&duration=${duration}&code=${code}&autoclose=${auto_close}"

# Close any alert still up so they never stack. Window/tab title is set by
# alert.html and contains "Command Finished".
__iyf_close_alerts() {
  local app=$1
  case "$app" in
    *Chrome*|*Brave*|*Edge*)
      osascript -e "tell app \"$app\" to close (every window whose name contains \"Command Finished\")" 2>/dev/null
      ;;
    *Safari*)
      osascript -e "tell app \"Safari\" to close (every tab of every window whose name contains \"Command Finished\")" 2>/dev/null
      ;;
  esac
}

app=""
if [[ -d "/Applications/Google Chrome.app" ]]; then
  app="Google Chrome"
elif [[ -d "/Applications/Brave Browser.app" ]]; then
  app="Brave Browser"
elif [[ -d "/Applications/Microsoft Edge.app" ]]; then
  app="Microsoft Edge"
fi

if [[ -n "$app" ]]; then
  __iyf_close_alerts "$app"
  open -n -a "$app" --args --start-fullscreen --app="$url" &>/dev/null &
  # `open -n` shows the window but macOS often leaves keyboard focus on the
  # terminal, so Esc never reaches the alert (you'd have to click first). Pull
  # the browser frontmost once the new window exists so it becomes the key
  # window and receives keystrokes. Backgrounded so we don't stall the caller.
  osascript -e 'delay 0.4' -e "tell application \"$app\" to activate" &>/dev/null &
else
  open -a Safari "$url" &>/dev/null &
  osascript -e 'delay 0.5' -e 'tell application "Safari" to activate' \
    -e 'tell application "System Events" to tell process "Safari" to keystroke "f" using {command down, control down}' \
    &>/dev/null &
fi
