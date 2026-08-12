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
- MIDImunger is a normal macOS windowed app, not a background-only helper, but if you leave it running and switch to another app it should continue monitoring MIDI because it keeps its CoreMIDI source connections open until you quit.
- With `No MIDI Thru` selected, MIDImunger is primarily a monitor and should usually coexist with other MIDI apps without materially affecting them.
- If `MIDI Thru Destination` is set to an output, or if you use commands such as `All Notes Off`, MIDImunger actively sends MIDI and can affect other apps or hardware that are also listening on the same routes.
- MIDImunger suppresses the obvious case of routing an endpoint back into itself, but it does not prevent every possible duplicate path that can arise when multiple MIDI apps are running at the same time.
