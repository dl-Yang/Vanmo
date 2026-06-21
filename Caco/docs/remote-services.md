# Remote Services Migration

## Priority

1. Emby and Jellyfin: HTTP + JSON, highest reuse from the iOS implementation.
2. WebDAV: PROPFIND + XML parser, moderate effort.
3. Plex: HTTP + XML and token semantics, isolated after Emby/Jellyfin.
4. SMB: requires PoC before full support.
5. FTP, SFTP, NFS and DLNA: second-wave protocols because the iOS side is not production-complete.

## SMB Decision

SMB must stream through PrefetchProxy:

```text
SMB credentials -> SMB adapter -> PrefetchProxy -> http://127.0.0.1:<port>/stream/<id> -> PlayerEngine
```

This avoids password-bearing `smb://user:pass@host/path` URLs and keeps the player engine protocol-agnostic.

## Implementation Notes

- `RemoteFileService` mirrors the iOS protocol shape but returns string URIs instead of Swift `URL`.
- `MediaServerService` exposes `AsyncIterable<ServerMediaItem[]>` for paged imports.
- WebDAV XML parsing is isolated behind `parsePropfind` so it can switch between `xml.ConvertXML` and `fast-xml-parser`.
- Plex is intentionally separate from Emby/Jellyfin because the API shape and auth semantics differ.
