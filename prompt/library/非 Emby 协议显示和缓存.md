# 非Emby 协议：
问题1：SMB/WebDAV/FTP/NFS/本地等未适配首页 CollectionFolder 形式。它们走 MediaScanner 递归扫描写入 SwiftData MediaItem（MediaScanner.swift），首页无对应区块，只能经「继续观看/收藏/搜索」间接出现。

问题2：本地文件能写入 SwiftData，但 MediaItem 无 connectionId/协议来源字段（MediaItem.swift），无法按连接分组，故无法直接复用 CollectionFolder 布局。

后续方案：给 MediaItem 增加 sourceConnectionId: UUID?，MediaScanner.scanRemoteDirectory 写入时记录所属连接；首页基于 SwiftData 按 sourceConnectionId 聚合出「虚拟媒体库」区块（缓存天然来自 SwiftData，无需额外 JSON）。涉及 schema 迁移与扫描器改动，规模较大，单独迭代。