# Absorb Plus Windows media service patch

Based on pub.dev `audio_service_win` 0.0.3, with its MIT license retained.

- Release SMTC/MediaPlayer objects while the Flutter plugin and COM apartment are alive, instead of leaving static WinRT cleanup until process teardown.
- Revoke button events and own/join artwork tasks during cleanup.
- Forward SMTC button events through the app window's message queue so Flutter channel calls run on the platform thread.
- Treat missing artwork as empty, not a literal `null` file path, and use audio_service's cached artwork path when available.

The desktop smoke test exercises metadata submission, playback state changes, and clean shutdown. Physical media keys and artwork appearance still need visual/hardware verification. OS timeline scrubbing is not implemented by this plugin.
