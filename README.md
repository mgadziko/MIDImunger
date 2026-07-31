# MIDImunger

MIDImunger is a native macOS Swift app for watching all 16 MIDI channels at once.

Initial build goals:

- Listen to all available CoreMIDI input sources.
- Show the latest per-channel message in a wide monitoring window.
- Reuse the FB01Editor-style seven-segment LED readouts.
- Forward incoming MIDI data to a selected output destination in a MIDI Thru-style path.
- Offer quick selected-channel telemetry and an `All Notes Off` command.

Notes:

- MIDI has 16 channels per group. MIDI 2.0 still keeps 16 channels inside each UMP group, so the 16-channel layout is the right starting point for this app.
- Channel voice messages update the per-channel rows.
- System common, realtime, and SysEx traffic is surfaced in the footer because those messages do not naturally belong to one MIDI channel.
