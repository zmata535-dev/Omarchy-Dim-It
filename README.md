# Dim It

`dim-it` follows Omarchy's native idle cycle and runs independent timers for display dimming and bar foreground changes. Optional timers can turn off the monitor and lock the session. Display brightness and bar color restore when Omarchy reports activity.

While dimmed, Dim It temporarily changes the shared bar text and active foreground. Choose Gray, Dk Gray, or Black in its settings panel. On activity or restore, it returns to the prior user override or the live theme foreground. The settings panel keeps its regular popup colors.

The stock bar exposes its global foreground to third-party widgets as a read-only API. Dim It uses Omarchy's watched user `shell.toml` override to apply the temporary bar foreground without changing stock bar files, and restores the original `[bar] text` and `[bar] active` entries after activity.

Display dim, bar-color, and monitor-off timers are configured in Dim It's settings. The Omarchy screensaver and lock controls read and save `idle.screensaver` and `idle.lock` in `~/.config/omarchy/shell.json`; unrelated shell settings are preserved. Omarchy's own idle service handles the screensaver and lock. Dim It's timer clock follows the same native idle cycle, so at least one Omarchy idle timer must be enabled. Older `dimSeconds` settings migrate to the display and bar timers. Dim-It settings are stored in `~/.config/omarchy/dim-it.json`.

The optional **Bar Color During Playback** setting lets only the bar-color timer continue while an MPRIS player is playing, even when playback inhibits Omarchy's native idle monitor. It is off by default; display dim and monitor-off continue to follow Omarchy's native idle cycle, and Omarchy's screensaver and lock behavior is unchanged.
