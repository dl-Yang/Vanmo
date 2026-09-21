# iOS Subtitles and Appearance

**Product area:** Vanmo iOS player and Settings

## Subtitle Appearance

Settings and the in-player subtitle sheet show the same live preview while the user changes subtitle size, text color, or background color. The player persists those values as the global subtitle style.

Plain text subtitles and attributed text subtitles, including ASS/SSA text, apply the selected size, text color, and background color immediately. Basic attributed font traits should remain when the size is replaced. Attributed subtitles containing real text take precedence over an accompanying image. An attributed attachment containing only the object-replacement placeholder does not outrank the bitmap path. PGS, VobSub, and other bitmap subtitles apply the size control as image scaling; text and background color controls do not recolor bitmap pixels.

Bitmap subtitles first fit proportionally within the available subtitle area and then apply the user's size scale. The 12-, 18-, and 36-point settings must produce visibly different sizes without changing the image aspect ratio or exceeding the safe display width.

The default subtitle size is 18 points everywhere. Settings, the in-player sheet, persisted preferences, and rendered output must not expose different defaults.

## Media Detail Actions

The media-detail back and favorite actions remain 40-point circular controls with 24-point symbols and 16-point horizontal screen margins. iOS 26 and later use the system Liquid Glass effect. iOS 17–25 use an ultra-thin material fallback. Loading, selected favorite, disabled, and accessibility states remain available.

The back and favorite actions remain outside the panel drag surface. When the detail panel is collapsed, upward dragging starts from the bottom title/detail affordance. When expanded, downward dragging starts from the panel grabber. A list poster remains visible as a blurred low-resolution placeholder until the high-resolution poster for the same item finishes loading.

## Player Orientation and Picture in Picture

The in-player subtitle-format action appears only when the media exposes at least one embedded subtitle track. Media without embedded subtitles does not show that action; external subtitle appearance remains configurable through global Settings.

On iPhone, playback is presented by a dedicated full-screen UIKit hosting controller that requests a real landscape scene without a UIKit rotation animation. Closing playback places the outgoing player snapshot inside a black window-sized transition cover and restores portrait without a rotation animation. The snapshot remains centered at its original landscape dimensions, so it may crop or letterbox but must never stretch. The player then dismisses and the cover fades away. The underlying detail or tab must not participate in rotation, skew, black flash, or intermediate geometry. iPad keeps its existing orientation and multi-orientation behavior.

For KSPlayer content, returning Home while video is playing automatically starts Picture in Picture when the system reports it as possible. The direct `KSMEPlayer` adapter owns the PiP delegate and preserves playback during inactive/background transitions. Returning to the app restores the player without destroying or pausing its engine. Memory pressure must be diagnosed from a recorded memory warning or termination reason rather than inferred from a disappearing PiP window.

## Appearance

iOS offers exactly three appearance choices:

- Follow System
- Day
- Night

Removed light-only custom themes migrate to Day. The migration writes a valid stored value so Settings and the app root share one source of truth. macOS appearance is unchanged.

## Acceptance

- Changing text subtitle size or colors in either preview updates the sample immediately.
- The active player reflects in-player changes without reopening playback.
- SRT/VTT and ASS/SSA text follow the selected style; bitmap subtitles change scale only.
- MediaDetail uses Liquid Glass on iOS 26 and the material fallback on older supported systems.
- MediaDetail actions remain tappable while panel gestures work only in their intended regions, and poster loading never exposes a white frame.
- iPhone playback enters landscape and returns to portrait; automatic PiP remains visible and playing across one Home/foreground round trip.
- Settings displays only the three supported appearance options and applies each option correctly.

## Evidence Boundary

A Simulator recording proves only the captured UI and subtitle cases. It does not prove physical-device AVAudioSession behavior or every subtitle codec.
