# In Your Face for Terminal

A full-screen alert that pops up when a long-running terminal command finishes,
so you can switch away from the terminal and get yanked back the moment your
build / test / deploy is done.

When a command runs longer than a threshold, `iyf` opens a full-screen browser
window showing the command, how long it took, and its exit status (green for
success, red for failure). Click anywhere or press `Esc` to dismiss; it also
auto-closes after a configurable timeout.

## How it works

`iyf.sh` registers zsh `preexec` / `precmd` hooks:

- `preexec` records the command and a start timestamp before it runs.
- `precmd` runs after the command returns, measures elapsed time, and captures
  the exit code.
- If the command took longer than `IYF_THRESHOLD` seconds and isn't in the
  ignore list, it opens `alert.html` full-screen.

The alert is a local HTML file opened as a Chrome / Brave / Edge `--app` window
(falling back to Safari if none are installed). The command, duration, exit
code, and auto-close timeout are passed as URL query params.

## Install

Clone the repo to `~/.iyf` and source it from your `~/.zshrc`:

```sh
git clone <repo-url> ~/.iyf
echo 'source ~/.iyf/iyf.sh' >> ~/.zshrc
```

Then open a new shell (or run `source ~/.zshrc`).

Requires **zsh** on **macOS**. `python3` is used to URL-encode the command when
available, and degrades gracefully without it.

## Configuration

All settings are environment variables. Set them before `iyf.sh` is sourced
(e.g. export them earlier in `~/.zshrc`):

| Variable | Default | Description |
|----------|---------|-------------|
| `IYF_THRESHOLD` | `10` | Minimum command duration, in seconds, to trigger an alert. |
| `IYF_AUTO_CLOSE` | `90` | Seconds the alert stays up before auto-dismissing. Unset or non-positive falls back to 90. |
| `IYF_IGNORE_CMDS` | interactive tools (see below) | Space-separated list of command names to never alert on. Matched against the command's basename. |
| `IYF_ALERT_FILE` | `~/.iyf/alert.html` | Path to the alert HTML page. |

The default ignore list covers common interactive / long-lived foreground tools:

```
vim nvim nano emacs less more man htop top tig lazygit btm bottom glances
```

## Usage

It runs automatically once sourced. To preview the alert without waiting for a
slow command:

```sh
iyf make build      # shows the alert immediately for "make build"
```

## Dismissing the alert

- Click anywhere, or press `Esc`.
- It auto-dismisses after `IYF_AUTO_CLOSE` seconds — the progress bar along the
  bottom shows the time remaining.
- Opening a new alert first closes any previous alert window, so they don't
  stack up.
