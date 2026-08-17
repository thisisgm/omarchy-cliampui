# The forced sink rate is not readable from any PipeWire property

Measured on minipc 2026-08-17 with `clock.force-rate 44100` applied and a 44.1 kHz
stream playing.

```
pactl list short sinks           -> s32le 2ch 44100Hz          correct
sink  params.Format.rate         -> 44100                      correct
stream properties node.rate      -> 1/44100                    the stream, not the graph
stream properties default.clock.rate -> 48000                  stale, ignores the force
```

The only two places carrying the truth are `pactl` and the sink node's
`params.Format`. Quickshell's `PwNode` exposes `properties` but **not** `params`, so
the Format value is unreachable from QML.

**Decision:** the sink rate comes from a `pactl list short sinks` process, parsed by
`Model.sinkRateFromPactl`, fired on panel open, on track change, and two seconds
after each rate force. Everything else in the verdict stays push-based.

`default.clock.rate` is a trap: it reads like the graph rate, sits right there in the
stream's properties, and silently keeps saying 48000 while the sink actually runs at
44100. Anything binding to it would report resampling that is not happening.

## Stream identification

cliamp reaches PipeWire through the ALSA compatibility layer:

```
node.name        = alsa_playback.cliamp
application.name = PipeWire ALSA [cliamp]
```

Matching on `application.name` containing `cliamp` covers both, and is what the
service uses to find the stream node for routing and for the peak meter.
