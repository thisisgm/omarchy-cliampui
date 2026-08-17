# MPRIS Volume is not unity at 1.0

Measured on minipc 2026-08-17 against cliamp 1.63.2, both directions.

```
set via cliamp        set via MPRIS
 0 dB -> mpris 0.501187      1.0  -> +6 dB
-6 dB -> mpris 0.251189      0.5  -> -0.02 dB
-30dB -> mpris 0             0.25 -> -6.04 dB
+6 dB -> mpris 1
```

The mapping is amplitude relative to cliamp's **maximum**, not to unity:

```
mpris = 10 ^ ((dB - 6) / 20)
```

clamped to 0 at the bottom of the -30 dB range.

## Why this matters

`Volume` 1.0 means **+6 dB of boost**, not untouched samples. Feeding MPRIS volume
into the bit-perfect verdict would report a boosted signal as bit-perfect, which is
the exact class of wrong number the project directive forbids.

**Decision:** the unity gain condition reads `volume` from `cliamp status --json` and
requires it to be 0 dB. MPRIS volume is never consulted for the verdict.

Tolerance is `Math.abs(volumeDb) < 0.001`, tight on purpose. Setting volume through
MPRIS lands on -0.0206 dB rather than 0, and that genuinely is not unity: it scales
every sample by 0.9976. Only an exact 0 dB counts.

## Incidental finding

With a real track loaded, `status --json` also carries `position` and `duration` in
seconds, which earlier radio-only probes never showed. Position still comes from
MPRIS, which pushes instead of needing a poll, but the fields exist as a fallback.
