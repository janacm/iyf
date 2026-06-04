# CLAUDE.md — iyf (In Your Face)

A maximized-window alert that pops when a long terminal command / Claude turn
finishes. The alert is an HTML page (`alert.html`) opened by `iyf-show-alert.sh`
as a Chrome/Brave/Edge `--app` window (Safari fallback). Entry points:
`iyf.sh` (zsh hook) and `iyf-claude-hook.sh` (Claude Code hook) both call the
shared launcher `iyf-show-alert.sh`.

## The #1 architectural gotcha: an already-running browser drops `--args`

When the browser is **already running**, `open -a "Google Chrome" --args <flags>`
**silently discards every startup flag** — `--start-fullscreen`,
`--start-maximized`, `--window-size`, `--window-position`. The new `--app` window
just inherits whatever state macOS gives it (here: native full-screen). So you
**cannot** size or position the alert with flags passed to the user's main
browser instance. This is why swapping `--start-fullscreen`→`--start-maximized`
did nothing.

**The fix (current design):** launch the alert in a **dedicated, throwaway
browser instance** with its own `--user-data-dir` (default `~/.iyf-alert-profile`,
override `IYF_BROWSER_PROFILE`). A *fresh process* honors the geometry flags, so
the alert opens as an ordinary maximized window in the current Space (no
Space-slide animation, focus lands correctly). A previous alert instance is
`pkill`ed first so windows don't stack and every launch is a fresh process.

**Debugging consequence:** the dedicated instance is **invisible to**
`tell application "Google Chrome" ...` AppleScript (that targets the user's main
instance). Use **PID-based** tools to inspect it (see below).

## How to validate windowed-vs-fullscreen

Two **verified** methods (ranked). The discriminator either way: a normal macOS
window cannot sit under the menu bar, so the alert covering the menu bar /
reporting `display-mode: fullscreen` = fullscreen; sitting below it = windowed.

1. **Ask the user to look** — fastest and definitive. "Run `iyf test`: is there a
   *'press and hold esc to exit full screen'* banner, and is the menu bar
   visible?" Banner present / menu bar hidden = fullscreen. (You can't reliably
   screenshot it yourself — see dead-ends.)

2. **Page-reported display-mode via a one-shot local listener** — the verified
   programmatic check. The alert runs in a *separate* browser instance you can't
   read JS state out of, so a diagnostic page (swapped in via `IYF_ALERT_FILE`)
   `fetch`es its own `display-mode` to a tiny local HTTP listener:
   ```bash
   cd /tmp; PORT=47125; rm -f /tmp/iyf-probe-result
   python3 - "$PORT" <<'PY' &
   import http.server, sys
   class H(http.server.BaseHTTPRequestHandler):
       def do_GET(self): open('/tmp/iyf-probe-result','w').write(self.path); self.send_response(204); self.end_headers()
       def log_message(self,*a): pass
   s=http.server.HTTPServer(("127.0.0.1",int(sys.argv[1])),H); s.timeout=40; s.handle_request()
   PY
   L=$!
   cat > /tmp/iyf-diag.html <<HTML
   <!DOCTYPE html><html><head><title>Command Finished</title></head><body>
   <script>
   var dm=matchMedia('(display-mode: fullscreen)').matches?'FULLSCREEN'
     :(matchMedia('(display-mode: standalone)').matches?'standalone-window':'browser');
   fetch('http://127.0.0.1:${PORT}/r?dm='+dm+'&outH='+outerHeight,{mode:'no-cors'}).catch(function(){});
   </script></body></html>
   HTML
   IYF_ALERT_FILE=/tmp/iyf-diag.html IYF_AUTO_CLOSE=20 IYF_SNOOZE_MINUTES="" \
     ~/.iyf/iyf-show-alert.sh "validate" "1s" 0
   for i in $(seq 1 60); do [ -s /tmp/iyf-probe-result ] && break; sleep 0.5; done
   cat /tmp/iyf-probe-result   # dm=standalone-window & outH<screenH => maximized ✓ ; dm=FULLSCREEN => ✗
   pkill -f "user-data-dir=$HOME/.iyf-alert-profile"; kill $L 2>/dev/null
   ```
   Caveat: a **brand-new** `~/.iyf-alert-profile` is slow on first launch (profile
   init) and can miss the probe window — warm it with one throwaway launch first.

CGWindowList-by-PID geometry *sounds* cleaner (permission-free, no temp page) but
is **not reliable here**: JXA's CoreGraphics binding returns garbage
(`ObjC.deepUnwrap(CGWindowListCopyWindowInfo(...))` isn't an array) and the system
`python3` has no `Quartz` module. Only pursue it after `pip install
pyobjc-framework-Quartz`, then filter `CGWindowListCopyWindowInfo` by
`kCGWindowOwnerPID` + `kCGWindowLayer==0` and treat `bounds.Y > 0` as windowed.

## Dead-ends — don't waste time here

- **AppleScript Chrome window `mode`** is `"normal"` vs `"incognito"` — it has
  **nothing to do with fullscreen.** Do not use it to check fullscreen.
- **AppleScript `bounds`** is ambiguous: fullscreen *and* maximized both report a
  ~full-screen rect; only the **y-origin** (0 vs menu-bar height) disambiguates.
  And `set bounds` on a native-fullscreen window fails (`-1728`, handle
  invalidated) — that failure itself confirms native fullscreen.
- **`screencapture` CLI** and **System Events `AXFullScreen`** need permissions
  the terminal usually lacks (Screen Recording / Accessibility) and fail with
  *"could not create image from display"* / *"not allowed assistive access"*.
  (CGWindowList geometry is permission-free, but its JXA binding is unreliable —
  see the validation section.)
- **`osascript -l JavaScript ... $.NSScreen`** throws *"undefined is not an
  object"* without `ObjC.import('AppKit')`.

## Testing the launcher safely

- Run it directly, bypassing the shell hook:
  `IYF_AUTO_CLOSE=20 IYF_SNOOZE_MINUTES="" ~/.iyf/iyf-show-alert.sh "cmd" "1s" 0`
- `IYF_SNOOZE_MINUTES=""` skips spawning the snooze daemon during tests.
- `IYF_ALERT_FILE=/path/diag.html` swaps in a probe page.
- Between runs, kill the dedicated instance:
  `pkill -f "user-data-dir=$HOME/.iyf-alert-profile"`.
- The shell hook execs `~/.iyf/iyf-show-alert.sh` **fresh each time**, so edits to
  the launcher take effect on the next alert **without re-sourcing**. Re-sourcing
  `iyf.sh` only matters for changes to the hook logic in `iyf.sh` itself.
- `~/.iyf` is the installed clone the live hooks run from; it's separate from any
  dev checkout. After changing the launcher, `git -C ~/.iyf pull` to go live.

## Window geometry

Size = the **primary** display's `visibleFrame` (below the menu bar, above the
Dock), converted to the top-left coordinates `--window-position` expects. Read it
via JXA `NSScreen.screens[0]` — **not** Finder's `bounds of window of desktop`,
which returns the **union of all displays** on a multi-monitor setup and would
span every monitor.
