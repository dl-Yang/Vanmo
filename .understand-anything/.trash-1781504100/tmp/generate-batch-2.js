const fs = require('fs');

const inputJson = require('/Users/yingu/Vanmo/.understand-anything/tmp/ua-file-analyzer-input-2.json');
const extractResults = require('/Users/yingu/Vanmo/.understand-anything/tmp/ua-file-extract-results-2.json');

const nodes = [];
const edges = [];

const fileData = {
  ".cursorignore": {
    summary: "Cursor AI 的 Git 风格忽略文件，指定应从 AI 上下文中排除的文件和目录。",
    tags: ["配置", "忽略文件", "cursor"],
    type: "config"
  },
  ".understand-anything/.understandignore": {
    summary: "Understand-Anything 插件的忽略文件，定义要从知识图谱生成中排除的路径。",
    tags: ["配置", "忽略文件", "understand-anything"],
    type: "config"
  },
  "scripts/build-ffmpeg-ios.sh": {
    summary: "用于为 iOS 下载和构建包含各种架构和依赖项的 FFmpeg 的 Shell 脚本。",
    tags: ["构建系统", "脚本", "ffmpeg", "ios"],
    type: "file"
  },
  "Vanmo.xcodeproj/project.pbxproj": {
    summary: "Xcode 项目配置文件，定义 Vanmo 应用程序的目标、构建设置和文件引用。",
    tags: ["配置", "xcode", "构建系统"],
    type: "config"
  },
  "Vanmo.xcodeproj/xcshareddata/xcschemes/Vanmo.xcscheme": {
    summary: "Xcode scheme 配置文件，定义 Vanmo 目标的构建、运行、测试和分析操作。",
    tags: ["配置", "xcode", "scheme"],
    type: "config"
  },
  "Vanmo/App/AppState.swift": {
    summary: "全局应用程序状态对象，管理整个应用程序的路由、选项卡和共享 UI 状态。",
    tags: ["状态管理", "路由", "app-state"],
    type: "file"
  },
  "Vanmo/App/ContentView.swift": {
    summary: "根 SwiftUI 视图，设置主选项卡导航并处理顶层路由。",
    tags: ["ui-view", "根组件", "导航"],
    type: "file"
  },
  "Vanmo/App/VanmoApp.swift": {
    summary: "Vanmo iOS 应用程序的主入口点，配置应用程序生命周期并注入全局状态。",
    tags: ["入口点", "应用生命周期", "swiftui"],
    type: "file"
  },
  "Vanmo/Core/Metadata/FileNameParser.swift": {
    summary: "解析媒体文件名的实用工具，用于提取标题、年份、季数和集数。",
    tags: ["工具函数", "解析", "元数据"],
    type: "file"
  },
  "Vanmo/Core/Metadata/MetadataService.swift": {
    summary: "协调从 TMDb 等各种来源获取元数据的服务层。",
    tags: ["服务", "元数据", "协调器"],
    type: "file"
  },
  "Vanmo/Core/Metadata/TMDbModels.swift": {
    summary: "表示来自 TMDb API 响应的数据模型，包括电影、电视节目和演员详情。",
    tags: ["数据模型", "tmdb", "api响应"],
    type: "file"
  },
  "Vanmo/Core/Metadata/TMDbService.swift": {
    summary: "与 The Movie Database (TMDb) 交互以获取媒体元数据和图像的 API 客户端。",
    tags: ["api客户端", "tmdb", "服务"],
    type: "file"
  },
  "Vanmo/Core/Network/EmbyService.swift": {
    summary: "与 Emby 媒体服务器交互的综合服务实现，处理身份验证、浏览和播放。",
    tags: ["服务", "emby", "媒体服务器", "api客户端"],
    type: "file"
  },
  "Vanmo/Core/Network/JellyfinService.swift": {
    summary: "Jellyfin 服务器的服务实现，扩展或包装了兼容 Emby 的 API。",
    tags: ["服务", "jellyfin", "媒体服务器"],
    type: "file"
  },
  "Vanmo/Core/Network/LocalFolderService.swift": {
    summary: "用于从本地设备存储浏览和播放媒体文件的服务。",
    tags: ["服务", "本地存储", "文件系统"],
    type: "file"
  },
  "Vanmo/Core/Network/NetworkError.swift": {
    summary: "定义各种远程服务中使用的常见网络和 API 错误。",
    tags: ["错误处理", "网络", "类型定义"],
    type: "file"
  },
  "Vanmo/Core/Network/PlexService.swift": {
    summary: "与 Plex 媒体服务器交互的服务实现，解析 Plex XML/JSON 响应。",
    tags: ["服务", "plex", "媒体服务器", "api客户端"],
    type: "file"
  },
  "Vanmo/Core/Network/ServiceFactory.swift": {
    summary: "工厂模式实现，用于根据服务器类型实例化适当的远程服务。",
    tags: ["工厂", "服务创建", "依赖注入"],
    type: "file"
  },
  "Vanmo/Core/Network/SMBService.swift": {
    summary: "用于连接和浏览 SMB (服务器消息块) 网络共享的服务。",
    tags: ["服务", "smb", "网络共享"],
    type: "file"
  },
  "Vanmo/Core/Network/WebDAVService.swift": {
    summary: "用于与 WebDAV 服务器交互以浏览和流式传输媒体文件的服务。",
    tags: ["服务", "webdav", "网络共享"],
    type: "file"
  },
  "Vanmo/Core/Player/KSPlayerEngine.swift": {
    summary: "使用 KSPlayer 的播放器引擎实现，提供高级播放功能。",
    tags: ["播放器引擎", "ksplayer", "媒体播放"],
    type: "file"
  },
  "Vanmo/Core/Player/PlayerEngine.swift": {
    summary: "定义媒体播放器引擎标准接口的协议，以及默认的 AVPlayer 实现。",
    tags: ["协议", "播放器引擎", "avplayer"],
    type: "file"
  },
  "Vanmo/Core/Player/PlayerEngineFactory.swift": {
    summary: "根据媒体格式和设置创建适当播放器引擎（AVPlayer 或 KSPlayer）的工厂。",
    tags: ["工厂", "播放器引擎", "媒体播放"],
    type: "file"
  },
  "Vanmo/Core/Player/PlayerState.swift": {
    summary: "表示媒体播放器当前状态、配置和章节的数据模型和枚举。",
    tags: ["状态管理", "数据模型", "播放器状态"],
    type: "file"
  },
  "Vanmo/Core/Player/Prefetch/FetchLimiter.swift": {
    summary: "用于对媒体预取操作进行速率限制或并发限制的实用工具。",
    tags: ["工具函数", "并发", "预取"],
    type: "file"
  }
};

const swiftStructures = {
  "scripts/build-ffmpeg-ios.sh": [
    { type: "function", name: "download_source", lineRange: [23, 36], summary: "下载 FFmpeg 源代码。", tags: ["下载", "源码"] },
    { type: "function", name: "build_arch", lineRange: [38, 112], summary: "为特定架构构建 FFmpeg。", tags: ["构建", "编译"] },
    { type: "function", name: "install_output", lineRange: [114, 141], summary: "安装编译好的 FFmpeg 库。", tags: ["安装", "输出"] }
  ],
  "Vanmo/App/AppState.swift": [
    { type: "class", name: "AppState", lineRange: [5, 54], summary: "全局应用程序状态对象，管理整个应用程序的路由、选项卡和共享 UI 状态。", tags: ["状态管理", "路由", "app-state"] }
  ],
  "Vanmo/App/ContentView.swift": [
    { type: "class", name: "ContentView", lineRange: [3, 68], summary: "根 SwiftUI 视图，设置主选项卡导航并处理顶层路由。", tags: ["ui-view", "根组件", "导航"] }
  ],
  "Vanmo/App/VanmoApp.swift": [
    { type: "class", name: "VanmoApp", lineRange: [6, 44], summary: "Vanmo iOS 应用程序的主入口点，配置应用程序生命周期并注入全局状态。", tags: ["入口点", "应用生命周期", "swiftui"] },
    { type: "class", name: "VanmoAppDelegate", lineRange: [45, 55], summary: "处理生命周期事件和方向锁定的应用程序委托。", tags: ["app-delegate", "生命周期"] }
  ],
  "Vanmo/Core/Metadata/FileNameParser.swift": [
    { type: "class", name: "FileNameParser", lineRange: [17, 127], summary: "解析媒体文件名的实用工具，用于提取标题、年份、季数和集数。", tags: ["工具函数", "解析", "元数据"] }
  ],
  "Vanmo/Core/Metadata/MetadataService.swift": [
    { type: "class", name: "MetadataResult", lineRange: [96, 112], summary: "表示元数据获取操作结果的数据模型。", tags: ["数据模型", "元数据", "结果"] }
  ],
  "Vanmo/Core/Metadata/TMDbModels.swift": [
    { type: "class", name: "TMDbMovie", lineRange: [14, 30], summary: "表示来自 TMDb 的电影的数据模型。", tags: ["数据模型", "tmdb", "电影"] },
    { type: "class", name: "TMDbMovieDetail", lineRange: [31, 60], summary: "表示来自 TMDb 的详细电影信息的数据模型。", tags: ["数据模型", "tmdb", "电影详情"] },
    { type: "class", name: "TMDbTVShow", lineRange: [61, 77], summary: "表示来自 TMDb 的电视节目的数据模型。", tags: ["数据模型", "tmdb", "电视节目"] },
    { type: "class", name: "TMDbTVDetail", lineRange: [78, 103], summary: "表示来自 TMDb 的详细电视节目信息的数据模型。", tags: ["数据模型", "tmdb", "电视详情"] }
  ],
  "Vanmo/Core/Metadata/TMDbService.swift": [
    { type: "class", name: "TMDbService", lineRange: [3, 124], summary: "与 The Movie Database (TMDb) 交互以获取媒体元数据和图像的 API 客户端。", tags: ["api客户端", "tmdb", "服务"] }
  ],
  "Vanmo/Core/Network/EmbyService.swift": [
    { type: "class", name: "EmbyService", lineRange: [4, 709], summary: "与 Emby 媒体服务器交互的综合服务实现。", tags: ["服务", "emby", "媒体服务器"] }
  ],
  "Vanmo/Core/Network/JellyfinService.swift": [
    { type: "class", name: "JellyfinService", lineRange: [14, 54], summary: "Jellyfin 服务器的服务实现，扩展或包装了兼容 Emby 的 API。", tags: ["服务", "jellyfin", "媒体服务器"] }
  ],
  "Vanmo/Core/Network/LocalFolderService.swift": [
    { type: "class", name: "LocalFolderService", lineRange: [8, 147], summary: "用于从本地设备存储浏览和播放媒体文件的服务。", tags: ["服务", "本地存储", "文件系统"] }
  ],
  "Vanmo/Core/Network/NetworkError.swift": [
    { type: "class", name: "NetworkError", lineRange: [3, 23], summary: "定义各种远程服务中使用的常见网络和 API 错误。", tags: ["错误处理", "网络", "类型定义"] }
  ],
  "Vanmo/Core/Network/PlexService.swift": [
    { type: "class", name: "PlexService", lineRange: [11, 483], summary: "与 Plex 媒体服务器交互的服务实现，解析 Plex XML/JSON 响应。", tags: ["服务", "plex", "媒体服务器"] }
  ],
  "Vanmo/Core/Network/ServiceFactory.swift": [
    { type: "class", name: "RemoteServiceFactory", lineRange: [3, 25], summary: "工厂模式实现，用于根据服务器类型实例化适当的远程服务。", tags: ["工厂", "服务创建", "依赖注入"] }
  ],
  "Vanmo/Core/Network/SMBService.swift": [
    { type: "class", name: "SMBService", lineRange: [13, 236], summary: "用于连接和浏览 SMB (服务器消息块) 网络共享的服务。", tags: ["服务", "smb", "网络共享"] }
  ],
  "Vanmo/Core/Network/WebDAVService.swift": [
    { type: "class", name: "WebDAVService", lineRange: [13, 410], summary: "用于与 WebDAV 服务器交互以浏览和流式传输媒体文件的服务。", tags: ["服务", "webdav", "网络共享"] }
  ],
  "Vanmo/Core/Player/KSPlayerEngine.swift": [
    { type: "class", name: "KSPlayerEngine", lineRange: [7, 376], summary: "使用 KSPlayer 的播放器引擎实现，提供高级播放功能。", tags: ["播放器引擎", "ksplayer", "媒体播放"] }
  ],
  "Vanmo/Core/Player/PlayerEngine.swift": [
    { type: "class", name: "PlayerEngine", lineRange: [17, 41], summary: "定义媒体播放器引擎标准接口的协议。", tags: ["协议", "播放器引擎"] },
    { type: "class", name: "AVPlayerEngine", lineRange: [56, 343], summary: "PlayerEngine 协议的默认 AVPlayer 实现。", tags: ["播放器引擎", "avplayer"] }
  ],
  "Vanmo/Core/Player/PlayerEngineFactory.swift": [
    { type: "class", name: "PlayerEngineFactory", lineRange: [23, 39], summary: "根据媒体格式和设置创建适当播放器引擎（AVPlayer 或 KSPlayer）的工厂。", tags: ["工厂", "播放器引擎", "媒体播放"] }
  ],
  "Vanmo/Core/Player/PlayerState.swift": [
    { type: "class", name: "PlayerConfig", lineRange: [52, 70], summary: "表示媒体播放器配置的数据模型。", tags: ["数据模型", "播放器配置"] }
  ],
  "Vanmo/Core/Player/Prefetch/FetchLimiter.swift": [
    { type: "class", name: "FetchLimiter", lineRange: [1, 26], summary: "用于对媒体预取操作进行速率限制或并发限制的实用工具。", tags: ["工具函数", "并发", "预取"] }
  ]
};

extractResults.results.forEach(file => {
  const meta = fileData[file.path];
  if (!meta) {
    console.error("Missing metadata for", file.path);
    return;
  }
  
  let complexity = "simple";
  if (file.nonEmptyLines > 200) complexity = "complex";
  else if (file.nonEmptyLines > 50) complexity = "moderate";

  const nodeId = `${meta.type}:${file.path}`;
  
  nodes.push({
    id: nodeId,
    type: meta.type,
    name: file.path.split('/').pop(),
    filePath: file.path,
    summary: meta.summary,
    tags: meta.tags,
    complexity: complexity
  });

  const imports = inputJson.batchImportData[file.path] || [];
  imports.forEach(imp => {
    edges.push({
      source: nodeId,
      target: `file:${imp}`,
      type: "imports",
      direction: "forward",
      weight: 0.7
    });
  });

  const structures = swiftStructures[file.path] || [];
  structures.forEach(struct => {
    const structId = `${struct.type}:${file.path}:${struct.name}`;
    nodes.push({
      id: structId,
      type: struct.type,
      name: struct.name,
      filePath: file.path,
      lineRange: struct.lineRange,
      summary: struct.summary,
      tags: struct.tags,
      complexity: "simple"
    });
    edges.push({
      source: nodeId,
      target: structId,
      type: "contains",
      direction: "forward",
      weight: 1.0
    });
  });
});

const output = {
  nodes,
  edges
};

fs.writeFileSync('/Users/yingu/Vanmo/.understand-anything/intermediate/batch-2.json', JSON.stringify(output, null, 2));
console.log(`Wrote ${nodes.length} nodes and ${edges.length} edges to batch-2.json`);
