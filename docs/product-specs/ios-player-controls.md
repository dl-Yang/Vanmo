# iOS Player Controls

**Product area:** Vanmo iOS full-screen player

**Status:** In progress

## Seek Preview

Dragging the progress thumb shows a compressed preview frame above the slider together with the target time. The preview floats above the track and does not change the progress bar's layout height. A horizontal scrub gesture on the video surface keeps the existing center time card and adds the same preview frame above the time. Live streams hide both the progress bar and seek preview. Preview frames are reduced (about 160–200 pt wide) and are not source quality.

KSPlayer scrubbing keeps the playing picture running. The first drag starts a second muted KSPlayer that only keyframe-seeks. Emby, Jellyfin, and Plex open that player on the original URL. SMB, FTP, SFTP, and other proxied sources register a new prefetch token, separate from playback. Closing playback shuts down the preview player and unregisters its token. AVPlayer keeps `AVAssetImageGenerator` and does not pause or seek the picture while scrubbing.

Preview generation must not open a second libavformat context for SMB, FTP, or SFTP while that file is already playing.

While the user is scrubbing, the bottom current-time label follows the target time.

## Video Quality

The player top bar exposes a quality capsule with 360p, 480p, 720p, 1080p, and Original. On Emby and Jellyfin, a lower choice asks PlaybackInfo for a transcoded HLS playlist at that height and bitrate, plays it with AVPlayer, and resumes from the current position. Plex requests a transcoded HLS playlist. Original keeps the direct file URL. If the transcode URL fails to open, playback uses the direct file. An HLS item already playing on AVPlayer selects the matching rendition with `preferredMaximumResolution` and `preferredPeakBitRate`. Local files and SMB, FTP, and SFTP keep playing the original bitstream. A source shorter than the selected height falls back to Original. There is no AI enhancement control.

## Skip Intro

A Skip Intro capsule appears above the progress bar when the current time is inside a known intro window and more than about two seconds remain. The window comes from, in override order:

1. A user mark of “intro ends here,” stored locally by `mediaKey`
2. Emby, Jellyfin, or Plex intro chapters/markers
3. Chapter titles matching intro, opening, 片头, or OP

The chapter sheet is always available and includes the mark action even when no chapters exist. The mark is local only and does not change the CloudKit schema.

## AirPlay

The top bar includes a system AirPlay route picker. HTTP(S) progressive MP4/MOV/M4V and HLS on the AVFoundation path can use video AirPlay. KSPlayer formats such as MKV, SMB, FTP, and SFTP cannot send decoded video to Apple TV; selecting an AirPlay route shows that video AirPlay is unavailable and that system screen mirroring remains possible. Chromecast and DLNA are out of scope.

## Figma

iOS Player frames live in Vanmo iOS file `miM6YTQAnerz6SgkkYZMjo`, page `Player` (`599:3`).

## Acceptance

- iOS Simulator: scrub preview on the slider and gesture overlay, live quality switch without a black screen, skip-intro visibility after a chapter title or manual mark
- Physical device: AirPlay route picker and either video AirPlay on a compatible stream or the unsupported-format notice
- A compile or package test is not AirPlay evidence
