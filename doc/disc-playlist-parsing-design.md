# 蓝光原盘 / ISO Playlist 解析层设计

状态：设计 + 骨架（本阶段，P0「HDR / ISO / BDMV 探测产品化」）。完整可播放实现属 P1「蓝光 ISO / 原盘播放」。

## 背景与现状

- 格式识别已统一到 `MediaFormatProbe.isDiscImage(_:)`：`.iso`、`.mpls`、路径含 `/BDMV/` 判定为原盘。
- `PlayerEngineFactory` 将 `.discImage` 路由到 `KSPlayerEngine`（PoC），能否播放完全取决于 KSPlayer/FFmpeg 内置能力，无 playlist 语义、无主片选择、无章节/音轨/字幕映射。
- 本阶段新增 `Core/Player/Disc/` 抽象层（`DiscPlaylistParser.swift`），定义协议与数据模型，提供占位实现，为 P1 落地铺路。

## 模块结构（目标）

```
Core/Player/Disc/
  DiscPlaylistParser.swift   // 协议 + 模型 + 占位实现（本阶段）
  ISODiscParser.swift        // P1：ISO 镜像挂载/读取 + BDMV 定位
  BDMVPlaylistParser.swift   // P1：.mpls / .clpi 解析
  DiscDataSource.swift       // P1：本地/远程 Range 读取抽象
```

## 数据模型（已在骨架中定义）

- `DiscStructureKind`：`isoImage` / `bdmvFolder` / `unknown`
- `DiscStructure`：`kind` + `mainPlaylist` + `playlists`
- `DiscPlaylist`：`id`(如 `00800.mpls`) + `title` + `duration` + `chapters` + `audioTracks` + `subtitleTracks` + `segments`
- `DiscSegmentRef`：片段相对路径（`BDMV/STREAM/xxxxx.m2ts`）+ 时长
- `DiscChapter` / `DiscTrackRef`

## 协议（已在骨架中定义）

- `DiscStructureParsing`：`detectStructureKind(at:)` + `parseStructure(at:) async throws`
- `DiscPlaylistSelecting`：`selectMainPlaylist(from:)`（默认取最长 playlist）
- `PlaceholderDiscParser`：识别结构种类；`parseStructure` 抛 `notImplemented`

## P1 落地计划

### 1. BDMV 目录结构

```
BDMV/
  index.bdmv          # 顶层索引
  MovieObject.bdmv    # 导航命令
  PLAYLIST/*.mpls     # playlist（播放顺序、章节、流选择）
  CLIPINF/*.clpi      # clip 信息（时长、流属性）
  STREAM/*.m2ts       # 实际音视频流
```

主片选择：解析 `PLAYLIST/*.mpls`，按 playlist 总时长排序，取最长者为主电影；过滤明显的菜单循环 playlist（极短或大量重复 segment）。

### 2. `.mpls` 解析要点

- Header：`MPLS` magic + 版本
- PlayList 段：PlayItem 列表（引用 `CLIPINF` 的 clip id、IN/OUT 时间）
- PlayListMark 段：章节标记
- STN_table：每个 PlayItem 的音轨/字幕/视频流条目（PID、编码、语言）
- 时长来自 clip 的 IN/OUT（45kHz 时基）累加

### 3. ISO 镜像

- UDF 文件系统读取，定位内部 `BDMV/`，复用 BDMV 解析
- 优先评估 libbluray（含 UDF + AACS 处理）封装为 SPM/xcframework；自研 UDF 仅作兜底
- AACS 加密原盘超出范围（需密钥），仅支持未加密/已解密结构

### 4. 远程 Range 读取

- 复用现有 `PrefetchProxy` / `RemoteFetcher`（HTTP Range）思路，抽象 `DiscDataSource`：
  - 本地：`FileHandle` 随机读
  - 远程（WebDAV/AList/HTTP）：Range 请求按需读取 `.mpls`/`.clpi` 与 `.m2ts` 片段
  - SMB：`SMBClient` 随机读
- 目标：无需整盘下载即可解析结构并边读边播

### 5. 与播放引擎集成

- `PlayerEngineFactory` 对 `.discImage` 先调用 `DiscStructureParsing.parseStructure`
- 成功：用主片的 segment 列表喂给 KSPlayer（拼接 m2ts 或定位单一主 m2ts），并把章节/音轨/字幕映射到现有 `Chapter` / `AudioTrackInfo` / `SubtitleTrackInfo`
- 失败/未实现：回退当前 KSPlayer 直喂 PoC 行为
- 提供主片/版本选择 UI（多 playlist 时）

## 风险与取舍

- libbluray 许可（GPL/LGPL）与 App Store 合规需评估；若不可用则自研 `.mpls` 解析（不含 AACS）。
- AACS/BD+ 加密原盘不支持。
- 远程整盘 ISO 的随机读取延迟较高，需缓存 `.mpls`/`.clpi` 元数据。
