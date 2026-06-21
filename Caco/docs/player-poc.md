# Player and PrefetchProxy PoC

## Goal

Validate the HarmonyOS playback stack before enabling complex formats and SMB streaming.

## PoC Order

1. System AVPlayer opens direct HTTP MP4 and local media URIs.
2. Player state callbacks update `PlayerViewModel`: loading, playing, paused, buffering, ended and error.
3. Progress persists through `PlaybackRepository` and `MediaRepository`.
4. PrefetchProxy exposes a local HTTP URL that supports Range requests.
5. WebDAV stream uses PrefetchProxy for Range forwarding.
6. SMB stream uses PrefetchProxy and never exposes credentials to the player.
7. ijkplayer or FFmpeg NDK opens MKV and reports duration, audio tracks and subtitle tracks.

## Acceptance

- First frame under 2 seconds for direct MP4 on local network.
- Seek within already buffered content under 500 ms.
- Resume position survives app restart.
- Range requests return correct `206` responses and `Content-Range` headers.
- Player logs never contain passwords, tokens or full credential-bearing URLs.
