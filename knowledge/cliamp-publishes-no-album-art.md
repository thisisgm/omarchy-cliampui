# cliamp publishes no album art, and stream:true does not mean unseekable

Found on 2026-08-17 by playing a real Navidrome track rather than a local test tone.
Local files hid all three of these.

## No artUrl anywhere

cliamp's MPRIS metadata carries `xesam:title`, `xesam:artist`, `xesam:album` and
`xesam:url`, and **never `mpris:artUrl`**. Verified for:

- a local FLAC with an embedded `METADATA_BLOCK_PICTURE` cover, which it ignores
- a Navidrome track, which has cover art on the server

`cliamp status --json` has no art field either, despite the binary containing an
`album_art_url` string.

**Workaround in use.** The status `path` for a Navidrome track is the full Subsonic
stream URL including its salted auth token:

```
https://host/rest/stream?c=cliamp&f=json&format=raw&id=XXX&s=SALT&t=TOKEN&u=USER&v=1.0.0
```

`Model.coverArtUrlFromStreamPath` rewrites that to `/rest/getCoverArt` keeping
`id`, `u`, `t`, `s`, `c`, `v` and appending `size`. The same token that authorises the
stream authorises the cover, so the panel shows artwork **without ever being given a
password**. It refuses anything that is not an `https://` Subsonic stream URL, so a
plaintext host cannot be reached and a local path yields nothing.

If cliamp ever starts publishing `mpris:artUrl`, that value wins.

## stream:true is set for library tracks, not just radio

A Navidrome track reports `"stream": true` exactly as a radio station does. Gating
seekability on it hides the scrubber on every library track.

The real distinction is **duration**: a Navidrome track carries `duration: 217`, radio
carries none. So `canSeek` is `lengthSec > 0`.

## Transcoding is judged by the URL, not the extension

A Subsonic stream URL has no file extension, so container sniffing returns nothing.
cliamp requests `format=raw`, and its absence on a `/rest/stream` URL is what means
the server re-encoded. `Model.transcodedFromPath` implements exactly that, and local
files still fall back to their container.

Consequence: the signal line shows no codec name for Navidrome tracks, because the
codec genuinely is not knowable from what cliamp exposes. It says
`44.1 kHz · bit-perfect` rather than guessing `FLAC`.
