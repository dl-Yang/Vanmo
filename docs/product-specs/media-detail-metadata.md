# Media Detail Metadata Loading

**Product area:** iOS and macOS media detail

## Supported Sources

Emby, Jellyfin, and Plex detail pages progressively enrich the base `MediaItem`. Local and
file-based items continue to render their available catalog fields without adding a new external
metadata provider.

## Loading Behavior

- The detail shell and available `MediaItem` fields render immediately, including a usable title,
  artwork placeholder, synopsis, and actions.
- Cached metadata, server detail, seasons, collections, and the first episode page load
  concurrently where their dependencies allow it.
- A completed request updates only the component that consumes its result. Metadata delivery must
  not publish one aggregate state change that invalidates the whole detail screen.
- The first episode page starts as soon as the season request identifies the selected season; it
  does not wait for cast, collections, or artwork.
- Stale or cancelled work from a previously opened item must not update the current detail.

## Artwork

Logo, poster, backdrop, cast profile, and episode artwork load independently from textual metadata.
Remote artwork caching must not delay the display of synopsis, ratings, genres, cast names,
collections, seasons, or episodes. Artwork failures preserve remote URLs or placeholders and do not
turn a successful metadata response into a failed detail load.

## Refresh

Automatic metadata loading follows the existing metadata preference. Manual refresh forces a new
server detail request while keeping currently displayed content visible until replacement values
arrive. Component-level failures retain already available data and expose the existing refresh
error affordance when appropriate.

## Acceptance

- With an empty metadata cache, base detail content appears without waiting for a network or image
  response.
- Detail, season, and collection requests overlap for a supported TV item.
- Text and list components become visible before deliberately delayed artwork completes.
- A metadata event invalidates only its observing detail component, not the root detail view.
- iOS and macOS preserve their existing platform-specific MediaDetail layout and interactions.
- Emby/Jellyfin and Plex issue one detail request per load generation.

## Evidence Boundary

Unit tests with delayed dependencies prove ordering, concurrency, cancellation, and cache behavior.
Debug timing logs prove only the recorded source and run. App compilation does not prove runtime
request overlap or SwiftUI invalidation boundaries.
