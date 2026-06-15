const fs = require('fs');

const inputPath = '/Users/yingu/Vanmo/.understand-anything/tmp/ua-arch-input.json';
const outputPath = '/Users/yingu/Vanmo/.understand-anything/intermediate/layers.json';

const input = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
const fileNodes = input.fileNodes || [];

const layers = [
  {
    "id": "layer:app-entry-state",
    "name": "应用入口与状态层",
    "description": "承载 Vanmo 的 @main App、根 ContentView 和全局 ObservableObject 状态装配，负责启动 SwiftUI 应用并连接顶层导航。",
    "nodeIds": []
  },
  {
    "id": "layer:playback-core",
    "name": "播放核心层",
    "description": "封装 AVFoundation、KSPlayer/FFmpeg 播放引擎、预取代理、播放状态和字幕解析等媒体播放核心能力。",
    "nodeIds": []
  },
  {
    "id": "layer:network-media-source",
    "name": "网络与媒体源层",
    "description": "实现本地文件夹、SMB、WebDAV、Plex、Emby 和 Jellyfin 等媒体源协议，并提供连接管理与浏览入口。",
    "nodeIds": []
  },
  {
    "id": "layer:metadata-scanning",
    "name": "元数据与媒体扫描层",
    "description": "负责文件名解析、媒体扫描、TMDb 请求与 Decodable 模型映射，为资料库和展示界面提供影片元数据。",
    "nodeIds": []
  },
  {
    "id": "layer:library-feature",
    "name": "媒体资料库功能层",
    "description": "组织媒体资料库、收藏、筛选、搜索和设置等 SwiftUI 功能模块的模型、ViewModel 与页面。",
    "nodeIds": []
  },
  {
    "id": "layer:ui-components-utils",
    "name": "通用组件与工具层",
    "description": "提供基础 UI 组件、颜色主题扩展、播放器界面控制以及工具类（如 Keychain、Logger、色彩提取），支撑各功能模块。",
    "nodeIds": []
  },
  {
    "id": "layer:resources-config",
    "name": "资源与配置层",
    "description": "包含 XcodeGen、Xcode project、Info.plist、entitlements、Assets.xcassets、Lottie JSON 和扫描忽略配置等应用资源与工程配置。",
    "nodeIds": []
  },
  {
    "id": "layer:docs-build-scripts",
    "name": "文档与构建脚本层",
    "description": "覆盖 README 开发说明、IPA 打包脚本和 FFmpeg iOS 构建脚本，支持项目理解、归档和第三方库产物生成。",
    "nodeIds": []
  }
];

// Reconstruct logic for assigning node IDs to correct layers
const assignedNodes = new Set();

function assign(nodeId, layerId) {
    if (assignedNodes.has(nodeId)) return;
    layers.find(l => l.id === layerId).nodeIds.push(nodeId);
    assignedNodes.add(nodeId);
}

for (const node of fileNodes) {
    const p = node.filePath;
    
    // Entry State
    if (p.includes('Vanmo/App/')) {
        assign(node.id, "layer:app-entry-state");
    }
    // Playback Core
    else if (p.includes('Vanmo/Core/Player/') || p.includes('Vanmo/Core/Subtitle/')) {
        assign(node.id, "layer:playback-core");
    }
    // Network Media Source
    else if (p.includes('Vanmo/Core/Network/') || p.includes('Vanmo/Features/Browser/') || p.includes('Vanmo/Shared/Protocols/')) {
        assign(node.id, "layer:network-media-source");
    }
    // Metadata Scanning
    else if (p.includes('Vanmo/Core/Metadata/') || p.includes('Vanmo/Core/Storage/')) {
        assign(node.id, "layer:metadata-scanning");
    }
    // Library Feature (Library, Search, Settings)
    else if (p.includes('Vanmo/Features/Library/') || p.includes('Vanmo/Features/Search/') || p.includes('Vanmo/Features/Settings/')) {
        assign(node.id, "layer:library-feature");
    }
    // UI Components Utils (Player Views, Shared Components/Extensions/Utils)
    else if (p.includes('Vanmo/Features/Player/') || p.includes('Vanmo/Shared/Components/') || p.includes('Vanmo/Shared/Extensions/') || p.includes('Vanmo/Shared/Utilities/')) {
        assign(node.id, "layer:ui-components-utils");
    }
    // Docs & Scripts
    else if (p.includes('README.md') || p.endsWith('.sh') || p === 'build_ipa.sh') {
        assign(node.id, "layer:docs-build-scripts");
    }
    // Everything else to Resources Config
    else {
        assign(node.id, "layer:resources-config");
    }
}

// Ensure all are assigned
if (assignedNodes.size !== fileNodes.length) {
    console.error(`Mismatch! Assigned ${assignedNodes.size} but total is ${fileNodes.length}`);
} else {
    console.log(`Successfully assigned all ${fileNodes.length} nodes into ${layers.length} layers.`);
}

fs.writeFileSync(outputPath, JSON.stringify(layers, null, 2));
