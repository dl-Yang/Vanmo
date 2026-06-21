# Vanmo 元数据缓存与刷新

## 概述

Vanmo 详情页的 Logo、评分、演职人员头像、电视剧单集封面等增强元数据，通过 **单条刷新 + 本地磁盘缓存** 提供。设计目标：

- **只刷新当前条目**，禁止全库批量刷新
- **先展示标题，Logo 加载成功后淡入替换**（避免空白）
- **Emby / Jellyfin / Plex** 媒体服务器为唯一元数据来源
- **设置页** 可开关自动下载、查看缓存占用、一键清空

根目录：`Application Support/Vanmo/MetadataCache/`

---

## 架构图

```
┌──────────────────────────────────────────────────────────────────┐
│                      MediaDetailView                              │
│  ┌─────────────────┐  ┌──────────────────┐  ┌─────────────────┐  │
│  │MediaTitleLogoView│  │ castSection      │  │ episodesSection │  │
│  │ displayRating   │  │ displayCastMembers│  │ episode backdrop│  │
│  └────────┬────────┘  └────────┬─────────┘  └────────┬────────┘  │
│           │ onAppear / 更多→刷新 │                     │           │
└───────────┼──────────────────────┼─────────────────────┼───────────┘
            │                      │                     │
            ▼                      ▼                     ▼
┌───────────────────────────────────────────────────────────────────┐
│              MetadataRefreshCoordinator (Actor)                    │
│  resolveSource → buildDraft → MetadataCache.save → apply to item   │
└───────────────┬───────────────────────────────┬───────────────────┘
                │                               │
     ┌──────────┴──────────┐         ┌──────────┴──────────┐
     ▼                     ▼         ▼                     ▼
 Emby/Jellyfin         Plex 电影/剧集              MetadataCache
 EmbyItemDetailFetcher  PlexItemDetailFetcher         (Actor)
 EmbyEpisodeFetcher     PlexEpisodeFetcher
```

---

## 核心文件

| 文件 | 路径 | 职责 |
|------|------|------|
| `MetadataCacheKey.swift` | `Core/Metadata/` | 由 `MediaItem` 推导缓存键（server / file） |
| `MetadataCacheRecord.swift` | `Core/Metadata/` | 缓存记录、剧集/演职人员子结构、本地路径解析 |
| `MetadataCache.swift` | `Core/Metadata/` | Actor：索引读写、图片下载、磁盘统计、清空 |
| `MetadataRefreshCoordinator.swift` | `Core/Metadata/` | 单条刷新路由与 draft 构建 |
| `CastMemberInfo.swift` | `Core/Metadata/` | 演职人员 cache / display 模型 |
| `MetadataService.swift` | `Core/Metadata/` | `applyCachedRecord` 写回 `MediaItem` |
| `EmbyService.swift` | `Core/Network/` | Emby/Jellyfin 详情、单集、Logo、People 头像 |
| `PlexService.swift` | `Core/Network/` | Plex 详情、单集列表 |
| `MediaTitleLogoView.swift` | `Shared/Components/` | 标题 → Logo 淡入替换 |
| `MediaDetailView.swift` | `Features/Library/Views/` | 刷新入口、局部 UI 状态、剧集增量合并 |
| `SettingsView.swift` | `Features/Settings/Views/` | 元数据 Section（自动下载、缓存管理） |

---

## 缓存键（MetadataCacheKey）

优先级：

1. **服务器媒体**：`server:{connectionId}:{serverId}` 或 `server:{serverId}`
2. **本地/远程文件**：`file:{fileURL.absoluteString}`

同一 `MediaItem` 在详情页刷新、缓存命中、UI 回写时使用同一键，避免重复下载。

---

## 刷新流程

### 入口

| 触发 | 行为 |
|------|------|
| 详情页 `onAppear` | 仅媒体服务器条目：`loadCachedMetadataIfNeeded()` → 若 `metadata.autoDownload == true` 则 `refresh(force: false)` |
| 更多 → **刷新** | 同上，`refresh(force: true)` |

本地文件夹、SMB、WebDAV 等来源**不支持**元数据刷新，详情页仅展示入库时已有字段。

### 来源路由（resolveSource）

| 条件 | 来源 | 构建方法 |
|------|------|----------|
| `fileURL.host == "plex-series"` | Plex 剧集 | `buildPlexSeriesDraft` |
| Plex stream URL host 与 PMS baseURL 一致 | Plex 电影 | `buildPlexMovieDraft` |
| host 为 `series` / `emby-container` / `emby-item`，或 stream URL host 与 Emby baseURL 一致 | Emby / Jellyfin | `buildEmbyLikeDraft` |
| 其他 | 不支持 | 抛出 `MetadataRefreshError.unsupportedSource` |

---

## 各来源字段映射

### Emby / Jellyfin

| 字段 | API / 逻辑 |
|------|------------|
| Logo | `Items/{id}/Images/Logo` |
| Backdrop | `Items/{id}/Images/Backdrop` |
| Cast | `People` 中 Actor → `Items/{personId}/Images/Primary` |
| 单集列表 | `EmbyEpisodeFetcher.fetchEpisodes(seriesId:)` |

### Plex

| 字段 | 逻辑 |
|------|------|
| 详情 | `PlexItemDetailFetcher.fetchDetail(ratingKey:)` |
| Episodes | `PlexEpisodeFetcher.fetchEpisodes(seriesRatingKey:)` |
| Cast | Plex Role 标签（仅名字，无头像时 UI 显示首字母占位） |
| Logo | Plex 通常不提供，缺失时保持文字标题 |

---

## 设置页

| 项 | 存储键 / API | 说明 |
|----|----------------|------|
| 自动从媒体服务器下载元数据 | `@AppStorage("metadata.autoDownload")`，默认 `true` | 关闭后进入详情页只读缓存，不自动网络刷新 |
| 元数据缓存大小 | `MetadataCache.diskSize()` | 递归统计 `MetadataCache` 目录占用 |
| 删除所有元数据缓存 | `MetadataCache.deleteAll()` | 删除整个目录与内存索引；**不删除 SwiftData 中的 MediaItem** |

---

## 已知限制

1. **单条刷新**：协调器 API 仅接受单个 `MediaItem`，无全库扫描接口。
2. **Plex 演员头像**：Plex API 不提供 profile 图，仅展示名字与首字母占位。
3. **Plex Logo**：通常无 Logo 图，详情页以文字标题为主。
4. **媒体库首页**：SMB / WebDAV 等文件协议不在首页展示；仅 Emby / Jellyfin / Plex 媒体库分区。

---

## 相关文档

- 播放器架构：[`player-architecture.md`](./player-architecture.md)
- 网络缓冲调优：[`player-buffering.md`](./player-buffering.md)
