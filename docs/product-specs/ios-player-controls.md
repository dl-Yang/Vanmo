# iOS Player Controls

**Product area:** Vanmo iOS full-screen player

**Status:** Completed

## Seek Preview

Dragging the progress bar and a horizontal scrub on the video surface use the same center card: a compressed preview frame and the target time. The progress bar itself does not draw a preview. Live streams hide both the progress bar and seek preview. Preview frames are reduced (about 160–200 pt wide) and are not source quality.

KSPlayer scrubbing keeps the playing picture running. The first drag starts a second muted KSPlayer that only keyframe-seeks, and uses Emby trickplay images when the server provides them. When playback already uses a prefetch proxy, the preview player opens that same localhost token. Progressive Emby, Jellyfin, and Plex playback registers that proxy; their HLS transcode playlists stay on the original URL. Closing playback shuts down the preview player and does not unregister the shared playback token. When a quality switch replaces or drops that token, the next scrub reopens the preview player. An Emby, Jellyfin, or Plex transcode playing on AVPlayer previews through the same second KSPlayer on the original file, unless the original is itself a playlist. Other AVPlayer playback keeps `AVAssetImageGenerator`. Neither preview pauses or seeks the playing picture.

The progress-bar gray span (`rgba(244,239,230,0.26)`) is locally cached media, not a loading percentage; the played portion is amber (`#FFB547`) on a `5pt` glass track with a `20×20` liquid glass lens-bead thumb housing `CatPawDot`. Loading chrome appears for every playback state other than playing and paused, including idle, loading, and buffering, and also while playback reports playing but the playhead has not moved for about 1.2 seconds. The play button inside the `30×30` pause pill becomes a spinning amber arc, and a glowing white dash travels clockwise along the inside of the screen edge above the controls, entering through the top-left corner each time loading chrome appears. With Reduce Motion the dash rests still across the top-left corner. The dash stays visible when the controls are hidden and disappears when playback or pause resumes. Vertical brightness (left half) and volume (right half) swipe gestures display `42pt` `VerticalGestureHUD` liquid glass side capsules with `.allowsHitTesting(false)` so gesture taps pass through. iPhone playback is presented after the scene is landscape.

A seek while paused, including Skip Intro and the 15-second buttons, stays paused and shows the frame at the new position once it decodes (verified on a local file; remote sources not yet walked).

Preview generation must not open a second libavformat context for SMB, FTP, or SFTP while that file is already playing.

While the user is scrubbing, the bottom current-time label follows the target time. Controls do not auto-hide or toggle away while the progress bar is held, so releasing it seeks to the target. (macOS: dragging the progress bar or the volume slider does not move the player window.)

KSPlayer on iOS does not pin its display link to the source frame rate, so idle playback keeps the source frame rate without growing audio-video drift.

## Video Quality

Quality selection lives inside the `画质` (`Quality`) tab of the `Tracks` popover (`PlayerTracksPopover`), offering `360p`, `480p`, `720p`, `1080p`, and `Original`. On Emby and Jellyfin, a lower choice asks PlaybackInfo for a transcoded HLS playlist at that height and bitrate, plays it with AVPlayer, and resumes from the current position. Plex requests a transcoded HLS playlist. Original keeps the direct file URL. If the transcode URL fails to open, playback uses the direct file. While a quality change reopens the source, the last picture stays frozen on screen until the new source shows its first frame, or for at most 3 seconds after it opens. After the switch, the player restores the saved subtitle choice when it names a track on the new source, or the preferred-language match when none is saved. An HLS item already playing on AVPlayer selects the matching rendition with `preferredMaximumResolution` and `preferredPeakBitRate`. Local files and SMB, FTP, and SFTP keep playing the original bitstream; on those sources, and when a transcode falls back to the direct file, `原画` stays active while the saved choice is kept for the next media-server item. A source shorter than the selected height plays Original without changing the saved choice. There is no AI enhancement control.

## Skip Intro

A Skip Intro capsule appears above the progress bar when the current time is inside a known intro window and more than about two seconds remain. The window comes from, in override order:

1. A user mark of “intro ends here,” stored locally by `mediaKey`
2. Emby, Jellyfin, or Plex intro chapters/markers
3. Chapter titles matching intro, opening, 片头, or OP

The chapter sheet is always available and includes the mark action even when no chapters exist. The mark is local only and does not change the CloudKit schema.

## Episode Selector & Tracks Popover

The `40pt` top bar pairs the title/episode/spec capsule on the left with circular `40×40` PiP (`CatLGPip`) and `40×40` AirPlay controls plus a `45×40` icon-only `CatLGCatSliders` `Tracks` popover toggle on the right. Below the floating progress scrubber, the bottom split control row places the `44pt` transport island (timestamp, divider, `-15s` cat-tail skip, `30×30` pause pill, `+15s` cat-tail skip, next episode) on the left and the `44pt` quick-action pills (conditional `Skip Intro` and playback speed toggle, rendered as `1x` by default) on the right. Tapping the `Tracks` toggle or the playback speed pill opens the `272pt` liquid glass `PlayerTracksPopover` (`字幕 / 音轨 / 画质 / 倍速`, sized compactly via `ViewThatFits` up to `132pt` scroll height), which houses subtitle selection, online subtitle search/style settings, audio tracks, video quality, playback rate, and a utility footer for scale mode, chapters/skip-intro marking, and `选集` (episodes) when the current item belongs to a series with loaded episode groups. Episodes come from the local library when it has more than one, otherwise from Emby/Jellyfin or Plex by `seriesId`. Items opened from the Files tab carry no series metadata, so they disable next-episode and hide the episode action.

## Now Playing

While a video is open, the system Now Playing card shows the item title, poster when it loads, elapsed time, and duration. Play, pause, a 15-second skip, and a position scrub from the lock screen, Control Center, or headphones control playback. Live streams show as live and do not offer skip or scrub. Closing the player clears the card.

## AirPlay

The top bar includes a `40×40` circular system AirPlay route picker (`AVRoutePickerView` filling the full circle hit target). HTTP(S) progressive MP4/MOV/M4V and HLS on the AVFoundation path can use video AirPlay. KSPlayer formats such as MKV, SMB, FTP, and SFTP cannot send decoded video to Apple TV; selecting an AirPlay route shows that video AirPlay is unavailable and that system screen mirroring remains possible. Chromecast and DLNA are out of scope.

## Figma

iOS Player chrome follows Vanmo iOS file `miM6YTQAnerz6SgkkYZMjo`, page `Black Cat Redesign` (`656:2`), frames `17 · Liquid Glass Player — Scrubbing Preview (852×393)` (`732:1536`), `18 · Liquid Glass Player — Popover & HUD (852×393)` (`732:1631`), and `Liquid Glass Player Icons` (`732:1511`) (superseding the earlier `07` / `08` layouts). macOS keeps its existing glass control layout inside the player window.

## Acceptance

- iOS Simulator: scrub preview on the slider and gesture overlay, live quality switch without a black screen, skip-intro visibility after a chapter title or manual mark
- Physical device: AirPlay route picker and either video AirPlay on a compatible stream or the unsupported-format notice
- A compile or package test is not AirPlay evidence
