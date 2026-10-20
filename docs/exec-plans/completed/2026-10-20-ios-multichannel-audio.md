# iOS Multichannel Audio Acceptance

**Status:** Completed

## Objective

Record the first multichannel-audio sample on iOS: track labeling, the Auto and Surround / Spatial Audio output modes on AirPods, and playback stability.

## Scope

- Device and build: iPhone 17 Pro, iOS 27.0.1, Debug build at `2ccc166`, AirPods.
- Media: `DTS-HRA5.1_VC1-23.976.mkv` from a Mac File Sharing share. 112.6 MB, 45 s, 20.0 Mb/s overall. VC-1 Advanced 1920x1080 and DTS-HD HRA with 6 channels (`ffprobe` on the Mac).
- Paths: iOS direct `smb://` playback, then the same file downloaded through Vanmo and played locally.
- Logs under `tem/log/` (not committed): `accept-20261020-step4.txt` (SMB) and `accept-20261020-step4b.txt` (local). Trace `tem/instruments/20261020-dts-vc1-smb.trace`.

## Out of Scope

- macOS multichannel output.
- AirPlay, HDMI, and wired multichannel routes.
- Code changes.

## Verification

### Output modes (local playback)

- Both rounds showed the audio track as `DTS·5.1` in the player's track menu.
- Every open logged `audio session configured, maxChannels: 2, routeChannels: 2` and `maxHWChannels=2` on AirPods. In Auto mode, `configureAudioOptions` therefore adds the `aformat=channel_layouts=stereo` filter. Surround / Spatial Audio mode calls `setSupportsMultichannelContent(true)` and adds no stereo filter.
- Auto round: Control Center showed Spatial Audio off.
- Surround / Spatial Audio round: Control Center showed Spatial Audio (Fixed). The operator heard a clear difference between the rounds, with a spatial sound field only in the second.
- The `[KSEngine] audio options` line logs the mode as `<private>`, so the log cannot map each of the four local opens to a mode. The mode difference rests on the operator's Control Center readings.

### Local playback stability

- Four local opens reached `ready` in 41–153 ms and `firstFrame` in 1.08–1.57 s.
- Steady samples held about 24 fps with no buffering. One open dropped 10 frames in its first steady sample, and another dropped 1 frame mid-play.
- A/V sync stayed within 4–44 ms, apart from one 186 ms sample right after a seek and the first sample of one open.
- Seeks recovered in 9–211 ms.

### iOS direct SMB playback

- The same file did not play through over `smb://`. In each of three logged opens, the picture stayed frozen or nearly frozen (frame-rate samples of 0.4–1.7) for about 25–35 s, played about 10 s at 24 fps, then entered buffering. The two buffering periods that ended lasted 51 s and 67 s. The others lasted until the operator closed the player. Audio stopped with the picture. The two opens without a seek reached 11.1 s after about 1.5 minutes and 33.9 s after about 3.75 minutes.
- KSPlayer reads had a median of 2.8 Mb/s over 95 five-second samples (range 0.2–10.6 Mb/s, 15 above 5 Mb/s), against 18–29 Mb/s of video bitrate in those samples.
- These opens reached `ready` in 2103–2559 ms. The 2026-10-12 matrix's iOS direct-SMB opens reached `ready` in 304–640 ms, so the link was slower on this day.
- A launched Time Profiler run during one SMB open averaged 0.063 cores. KSPlayer's video, read, and audio threads together used about 5.5 ms/s, so decoding was waiting for data and was not CPU-bound.
- Ping from the Mac (the SMB server) to the iPhone over Wi-Fi, taken after playback while the phone was idle, averaged 117 ms with a range of 12–425 ms. Wi-Fi power saving on an idle iPhone can raise that figure.

## Risks

- The 2026-10-12 matrix's iOS SMB runs used 3 Mb/s Jellyfish clips, and no earlier record names a higher-bitrate iOS SMB file.
- The cause of the low read rate was not measured. Serial libsmbclient reads over a high-latency link would fit the log, but read sizes and round trips were not captured, and this is one session on a slower-than-usual link.
- The Auto-mode result applies to a route that reports 2 output channels. Other spatial-capable routes were not walked.

## Progress Log

- 2026-10-20: On iPhone 17 Pro with AirPods, the DTS-HD HRA 5.1 file rebuffered over iOS direct SMB, with low CPU and reads at a median of 2.8 Mb/s. After downloading it through Vanmo, local playback was smooth. Auto showed Spatial Audio off, and Surround / Spatial Audio showed Spatial Audio (Fixed) with an audible spatial field.

## Open Decisions

- Whether Auto should keep multichannel output on AirPods and other spatial-capable routes that report 2 channels, instead of downmixing to stereo. This is a product decision.
