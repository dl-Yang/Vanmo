const fs = require('fs');
const path = require('path');

const pluginRoot = '/Users/yingu/.understand-anything-plugin';
const projRoot = '/Users/yingu/Vanmo';

const graphPath = path.join(projRoot, '.understand-anything/intermediate/assembled-graph.json');
const graph = JSON.parse(fs.readFileSync(graphPath, 'utf8'));

const layersPath = path.join(projRoot, '.understand-anything/intermediate/layers.json');
const layers = JSON.parse(fs.readFileSync(layersPath, 'utf8'));

let langContext = '';
['c', 'json', 'markdown', 'shell', 'swift', 'xml', 'yaml'].forEach(lang => {
  try { langContext += fs.readFileSync(path.join(pluginRoot, `languages/${lang}.md`), 'utf8') + '\n\n'; } catch(e) {}
});

let frameworkContext = '';
['swiftui', 'avfoundation', 'xctest', 'xcode'].forEach(fw => {
  try { frameworkContext += fs.readFileSync(path.join(pluginRoot, `frameworks/${fw}.md`), 'utf8') + '\n\n'; } catch(e) {}
});

let localeContext = '';
try { localeContext = fs.readFileSync(path.join(pluginRoot, `locales/zh.md`), 'utf8') + '\n\n'; } catch(e) {}

// Extract entry point from search (using some simple heuristics if README is not there)
let entryPoint = 'Vanmo/App/VanmoApp.swift';

const prompt = `Please execute the tour-builder instructions located at /Users/yingu/.understand-anything-plugin/agents/tour-builder.md. First read the instructions, then process the inputs below.

Create a guided learning tour for this codebase.
Project root: ${projRoot}
Write output to: ${projRoot}/.understand-anything/intermediate/tour.json
Project: Vanmo — Vanmo 是一个 Swift/SwiftUI iOS 媒体播放应用，围绕本地与网络媒体源、播放内核、资料库和应用状态管理组织代码。
Languages: c, entitlements, json, markdown, pbxproj, shell, swift, unknown, xcscheme, xml, yaml

**Additional context from main session:**

Project README (first 3000 chars):
\`\`\`
# Vanmo

一款类似 Infuse 的 iOS 视频播放器应用，支持多格式播放、网络串流、媒体库管理、字幕和元数据抓取。

## 功能特性

### 视频播放
- AVFoundation 硬件解码播放引擎
- 支持 MP4、MKV、AVI、MOV 等常见格式
- 手势控制：左右滑动快进快退、左侧亮度、右侧音量
\`\`\`

Project entry point: ${entryPoint}

Use the README to align the tour narrative with the project's own documentation. Start the tour from the entry point if one was detected. The tour should tell the same story the README tells, but through the lens of actual code structure.

> **Language directive**: Generate all textual content (summaries, descriptions, tags, titles, languageNotes, languageLesson) in **zh**. Maintain technical accuracy while using natural, native-level phrasing in the target language. Keep technical terms in English when no standard translation exists (e.g., "middleware", "hook", "barrel").

## Language Context
${langContext}
${frameworkContext}
## Output Language Guidelines
${localeContext}

Nodes (all file-level nodes — includes code files, config, document, service, pipeline, table, schema, resource, endpoint):
\`\`\`json
${JSON.stringify(graph.nodes.filter(n => ['file', 'config', 'document', 'service', 'pipeline', 'table', 'schema', 'resource', 'endpoint'].includes(n.type)).map(n => ({id: n.id, name: n.name, filePath: n.filePath, summary: n.summary, type: n.type})), null, 2)}
\`\`\`

Layers:
\`\`\`json
${JSON.stringify(layers.map(l => ({id: l.id, name: l.name, description: l.description})), null, 2)}
\`\`\`

Edges (all types — includes imports, calls, configures, documents, deploys, triggers, etc.):
\`\`\`json
${JSON.stringify(graph.edges, null, 2)}
\`\`\`
`;

fs.writeFileSync(path.join(projRoot, '.understand-anything/tmp/tour-prompt.txt'), prompt);
