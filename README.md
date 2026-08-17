# Cliamp

[cliamp](https://www.cliamp.stream/) in the Omarchy bar: what is playing, where it is
routed, and whether the audio reaching your DAC is bit-perfect.

The last one is the reason this exists. Nothing else on the machine can tell you that
a 44.1 kHz track is being quietly resampled to 48 kHz before it reaches the speakers,
which is what PipeWire does by default to everything.

## Features

- **Now playing** with album art, artist and album, straight from cliamp's MPRIS
  interface, so it costs nothing while the panel is shut.
- **A live level meter** driven by PipeWire's own peak data, not by a second process.
- **Transport**: play, pause, next, previous, shuffle and repeat, plus a scrubber that
  hides itself for radio rather than pretending a stream can be seeked.
- **Output routing** per application. Switching here moves cliamp's own stream and
  leaves the system default alone, so your notifications keep going where they were.
- **A signal verdict** that only says "bit-perfect" when it really is, and otherwise
  names the specific thing in the way.
- **Rate following**, on by default: the audio graph is retuned to the track's sample
  rate while cliamp plays, and released the moment it stops.

## The signal line

Three conditions must all hold before the words "bit-perfect" appear:

1. The server sent the original file. cliamp requests `format=raw` from Navidrome and
   gets untranscoded FLAC, so this normally holds for a self-hosted library.
2. The sink rate equals the stream rate, read back from the sink after any change,
   never assumed from the rate that was requested.
3. Gain is unity. cliamp must be at 0 dB, because any attenuation alters samples.

| What you see | What it means |
| --- | --- |
| `FLAC 44.1 kHz · bit-perfect` | samples reach the DAC untouched |
| `44.1 → 48 kHz · resampled` | the graph is at a different rate |
| `88.2 → 96 kHz · output has no 88.2` | the rate was requested and the hardware substituted another |
| `44.1 kHz · SBC-XQ · lossy` | a Bluetooth sink, which re-encodes and can never be bit-perfect |
| `FLAC 44.1 kHz · volume applied` | rates line up but a gain is being applied |
| `MP3 · transcoded by server` | the file was re-encoded before it ever arrived |

That third row matters more than it looks. Asking PipeWire for a rate the DAC does not
have lands on the nearest one it does, silently. The verdict is therefore always read
back from the sink, so the panel cannot claim a route it did not get.

## Keyboard

| Key | Action |
| --- | --- |
| `space` / `enter` | play or pause, or pick a device when the output list is open |
| `n` / `b` | next and back |
| `left` / `right` | seek 5 seconds, or move the cursor when the output list is open |
| `o` | open and close the output list |
| `s` | shuffle |
| `r` | repeat |
| `p` | toggle rate following |
| `l` | open and close the library list |
| `f` | open the player in a terminal, handing the daemon's socket over |
| `esc` | close |

Left click opens the panel, right click plays or pauses without opening it.

## Requirements

- `cliamp` on `PATH`
- PipeWire, with `pw-metadata` and `pactl` available, both of which ship with it
- `omarchy-audio-sink-availability`, part of Omarchy, used to hide outputs with
  nothing plugged into them
- `foot`, used for the handover terminal

## Settings

| Setting | Default | Notes |
| --- | --- | --- |
| Seconds between status refreshes | 2 | only polls while the panel is open |
| Match the audio graph rate to the track | on | see the warning below |
| Hide the icon when cliamp is not running | on | |
| Path to cliamp | empty | empty means find it on `PATH` |

## Notes worth reading once

**It runs headless.** `cliamp-daemon.service` keeps a daemon alive across logins, so
closing a terminal never stops the music. Pick a saved playlist from the panel's
Library section and it plays with nothing else open.

**Browsing the library still needs the terminal, once.** cliamp's Navidrome browser is
TUI only, so build a playlist there with `N`, then save it. After that the panel can
load it headlessly forever, because a saved playlist keeps resolved stream URLs.
cliamp maintains "Recently Played" by itself, so there is always one to resume.

**Opening the player hands the socket over.** cliamp cannot attach to a running
instance: launching it while the daemon holds the socket starts a second, IPC-less
copy that the panel cannot see. Pressing `f` runs `cliamp-session`, which stops the
daemon for exactly as long as the terminal is open and starts it again on exit. The
queue survives, because cliamp writes `resume.json`.

**Rate following affects every application, not just cliamp.** The sample rate belongs
to the whole audio graph. While your music plays at 44.1 kHz, a browser playing 48 kHz
audio is the thing being resampled instead. It is released as soon as playback stops,
so the effect lasts exactly as long as the music. Turn it off in settings if that trade
is wrong for you.

**Enable this or the stock Media widget, not both.** They will both show the same track.

**A hard shell crash can leave the graph rate forced.** The panel releases it on a
clean shutdown, and the setting is session scoped, so restarting PipeWire clears it:

```bash
systemctl --user restart pipewire
```

## Install

```bash
git clone https://github.com/thisisgm/omarchy-cliampui ~/.config/omarchy/plugins/github.thisisgm.cliampui
omarchy plugin enable github.thisisgm.cliampui
omarchy bar put github.thisisgm.cliampui --section right
```

## Removal

```bash
systemctl --user disable --now cliamp-daemon.service
rm -f ~/.local/share/systemd/user/cliamp-daemon.service
omarchy plugin disable github.thisisgm.cliampui
rm -rf ~/.config/omarchy/plugins/github.thisisgm.cliampui
```

## Development

`Model.js` is pure JavaScript with no QML imports, so it is covered by tests:

```bash
deno run --allow-read tests/model.test.js
```

The fixtures are lines a running cliamp actually printed, including the 88.2 kHz
substitution this machine performs.

## License

MIT
