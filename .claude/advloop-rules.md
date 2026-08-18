# Repo rules: io.github.thisisgm.cliampui

An Omarchy Quickshell bar plugin for the cliamp terminal music player. One box, one
user, one GPU, one monitor. Reviewers should judge against these rules, not against
general-purpose library conventions.

## Platform facts a finding must not contradict

- cliamp 1.63.2, Quickshell 0.3.0, Navidrome 0.63.2, PipeWire, Arch, single user.
- **One cliamp instance per user.** The daemon and the TUI share one socket.
- **cliamp's output rate is fixed at launch** (`sample_rate`, default 44100) and it
  resamples everything else internally. Only 22050, 44100, 48000, 96000 and 192000 are
  accepted, so 88.2 kHz can never play natively.
- **cliamp publishes no album art**, over MPRIS or in status. The panel derives cover
  URLs from the Subsonic stream path, reusing the salted token already in it.
- **`track.stream` is true for Navidrome library tracks, not just radio.** Seeking one
  skips to the next track, so the progress bar is deliberately not interactive for
  streams. A known duration is the real seekability test.
- **cliamp has no jump-to-track command**, only next and prev.
- **`cliamp load` starts playback by itself.** Measured. Sending a play after it is
  redundant.
- **`{"cmd":"lyrics"}` and `{"cmd":"history"}` exist on the socket but are undocumented.**
  Measured on the box.
- The panel never handles a password. Every Subsonic request reuses the salted token
  already present in a stream URL cliamp published.

## Design rules this plugin is held to

- **Stay OEM.** Reuse stock Omarchy mechanisms (`omarchy <group> <action>`, stock hooks,
  `qs.Ui` components, systemd user units) before writing anything custom. A finding that
  proposes hand-rolling something stock already does is wrong.
- **The plugin is strictly a display.** Data acquisition lives in an `omarchy-*` command
  or a helper script; the QML watches and renders.
- **`Model.js` is pure**: no QML imports, `var` and plain loops, coerce defensively,
  return a full default shape on failure rather than throwing. It is covered by
  `deno run --allow-read tests/model.test.js`.
- **Parse in `Model.js`, never in `Service.qml`.**
- **One handler per signal per QML object.** A second `onXChanged` in the same object is
  "Property value set multiple times" and silently removes the widget from the bar.
- Poll rates are manifest settings with clamps re-applied on read.
- Optimistic state where a click must feel instant, overwritten when the poll agrees.
- Errors elided to a sentence, never dumped.

## Comment style, and the carve-out that matters

- **QML: a two or three line comment stating a non-obvious timing or race constraint is
  the house style**, copied from the first-party Omarchy plugins. Do NOT flag multi-line
  QML comments as paragraphs.
- **Shell and Python: one line per comment.** Two stacked comment lines above the same
  thing is a paragraph and is a defect. A module docstring on a standalone helper is not
  a comment and is allowed.
- Every parser carries a sample-input comment showing the exact format it consumes.
- Name magic numbers.

## Scope

- **Scope is the spec.** Generality nobody asked for, states this platform cannot be in,
  knobs with a single caller, and modes nobody runs are defects. Code for the one shape
  this box produces and say so in a comment.
- A finding about a case the platform cannot produce should expect a rebuttal naming the
  platform fact rather than more code.

## Out of scope for this review

- The three files not touched by this change: `OutputSheet.qml`, `CliampIcon.qml`,
  `MarqueeText.qml`, plus `cliamp-source-rate` and `cliamp-daemon-rate-apply`.
- Publishing, screenshots and marketplace submission.

## Measured facts added after the first review rounds

- **Every command answers on the same socket as the status feed.** An acknowledgement is
  `{"ok":true}`, sometimes with one field (`{"ok":true,"shuffle":false}`), and an error
  is `{"ok":false,"error":".."}`. Only a status carries `state`. Routing an
  acknowledgement to parseStatus blanked the track and flickered the whole panel on
  every command.
- **A track with no lyrics answers `{"ok":false,"error":"no lyrics found"}`.**
  `refreshLyrics()` empties the list before it sends, so that reply needs no handling.
- **`cliamp load` starts playback itself.** A play sent after it is redundant.
- **PipeWire reports the output latency** on cliamp's own node: 167 ms to the AirPods,
  0 ms to the analog output. `pactl` reports 0 usec for every sink and cannot be used.
- **ListView writes `currentIndex` itself on every model reassignment**, which breaks a
  QML binding to it for good. The library cursor is therefore driven from the panel's
  own `cursorIndex`, never from `ListView.currentIndex` or `ListView.isCurrentItem`.
- **The socket seek takes a delta, not a position**, whatever `cliamp seek --help` says.
  Paused at 4.9 s, `{"cmd":"seek","value":60}` landed at 64.9 s.
- **Negative deltas work and clamp at zero.** Playing at 94.9 s, value -60 landed at
  35.9 s still playing; value -30 while paused landed exactly; value -999 landed at 0.0
  with no error and no track change.
- **Seeking a Navidrome stream skips to the next track** rather than moving within it.
  Measured mid-queue: index 2 of 13 at 22.7 s went to index 3 at 2.2 s. On the last
  track of a queue it presents as stopping, since there is nothing to advance to, which
  is what an earlier single measurement here wrongly generalised. `canSeek` excluding
  streams is load bearing either way.
- **Navidrome ignores `timeOffset` on `format=raw`**, so there is no server side offset
  to scrub a stream with short of transcoding, which would cost the verdict.
