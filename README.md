# Dim It

`dim-it` uses its own Quickshell idle monitor for bar foreground, display dimming, and monitor-off. When Omarchy idle is disabled, Dim-It also launches the screensaver and native lock. When Omarchy idle is enabled, Omarchy manages those two timers while Dim-It continues to manage bar color, display dimming, and monitor-off. Display brightness, monitor power, and bar color restore when user activity resumes.

While dimmed, Dim It temporarily changes the shared bar text and active foreground and makes the bar fully transparent. Choose Dark Gray or Black in its settings panel. On activity, widget unload, or restore, it returns to the prior bar background and foreground settings, preserving changes made to the theme while the override is active. The settings panel keeps its regular popup colors.

The stock bar exposes its global foreground to third-party widgets as a read-only API. Dim It uses Omarchy's watched user `shell.toml` override to apply the temporary bar foreground without changing stock bar files, and restores the original `[bar] text` and `[bar] active` entries after activity.

Display dim, bar-color, screensaver, monitor-off, and lock delays are stored in `~/.config/omarchy/dim-it.json`. When Omarchy idle is enabled, Dim It reads and updates Omarchy's native `idle.screensaver` and `idle.lock` values in `~/.config/omarchy/shell.json`. When Omarchy idle is disabled, Dim It uses its saved screensaver and lock delays, launching the Omarchy screensaver and native lock command itself. Monitor-off remains managed by Dim It's Quickshell idle monitor. Unrelated shell settings are preserved. Older `dimSeconds` settings migrate to the display and bar timers.

The optional **Bar Color During Playback** setting lets only the bar-color timer continue while an MPRIS player is playing, even when playback inhibits the normal idle monitor. It is off by default. Display dim, screensaver, monitor-off, and lock timers respect idle inhibitors. The Omarchy lock service remains enabled in both idle modes.
