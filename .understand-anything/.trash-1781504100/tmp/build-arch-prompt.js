const fs = require('fs');
const path = require('path');

const pluginRoot = '/Users/yingu/.understand-anything-plugin';
const projRoot = '/Users/yingu/Vanmo';
const graphPath = path.join(projRoot, '.understand-anything/intermediate/assembled-graph.json');
const graph = JSON.parse(fs.readFileSync(graphPath, 'utf8'));

const fileLevelTypes = new Set(['file', 'config', 'document', 'service', 'pipeline', 'table', 'schema', 'resource', 'endpoint']);

const fileNodes = graph.nodes.filter(n => fileLevelTypes.has(n.type)).map(n => ({
  id: n.id, type: n.type, name: n.name, filePath: n.filePath, summary: n.summary, tags: n.tags
}));
const importEdges = graph.edges.filter(e => e.type === 'imports');
const allEdges = graph.edges;

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

let dirTree = '';
try {
  dirTree = fs.readFileSync(path.join(projRoot, '.understand-anything/tmp/dir_tree.txt'), 'utf8');
} catch(e) {}

let previousLayers = '';
try {
  const meta = JSON.parse(fs.readFileSync(path.join(projRoot, '.understand-anything/meta.json'), 'utf8'));
  const oldGraph = JSON.parse(fs.readFileSync(path.join(projRoot, '.understand-anything/knowledge-graph.json'), 'utf8'));
  if (oldGraph.layers) {
    previousLayers = `
> Previous layer definitions (for naming consistency):
\`\`\`json
${JSON.stringify(oldGraph.layers, null, 2)}
\`\`\`

Maintain the same layer names and IDs where possible. Only add/remove layers if the file structure has materially changed.`;
  }
} catch(e) {}

const prompt = `Please execute the architecture-analyzer instructions located at /Users/yingu/.understand-anything-plugin/agents/architecture-analyzer.md. First read the instructions, then process the inputs below.

Analyze this codebase's structure to identify architectural layers.
Project root: ${projRoot}
Write output to: ${projRoot}/.understand-anything/intermediate/layers.json
Project: Vanmo — Vanmo 是一个 Swift/SwiftUI iOS 媒体播放应用，围绕本地与网络媒体源、播放内核、资料库和应用状态管理组织代码。

**Additional context from main session:**

Frameworks detected: SwiftUI, AVFoundation, XCTest, Xcode

Directory tree (top 2 levels):
${dirTree}

Use the directory tree, language context, and framework addendums (appended below) to inform layer assignments. Directory structure is strong evidence for layer boundaries. Non-code files (config, docs, infrastructure, data) should be assigned to appropriate layers — see the prompt template for guidance.

> **Language directive**: Generate all textual content (summaries, descriptions, tags, titles, languageNotes, languageLesson) in **zh**. Maintain technical accuracy while using natural, native-level phrasing in the target language. Keep technical terms in English when no standard translation exists (e.g., "middleware", "hook", "barrel").

${previousLayers}

## Language Context
${langContext}
${frameworkContext}
## Output Language Guidelines
${localeContext}

File nodes (all node types — includes code files, config, document, service, pipeline, table, schema, resource, endpoint):
\`\`\`json
${JSON.stringify(fileNodes, null, 2)}
\`\`\`

Import edges:
\`\`\`json
${JSON.stringify(importEdges, null, 2)}
\`\`\`

All edges (for cross-category analysis — includes configures, documents, deploys, triggers, etc.):
\`\`\`json
${JSON.stringify(allEdges, null, 2)}
\`\`\`
`;

fs.writeFileSync(path.join(projRoot, '.understand-anything/tmp/arch-prompt.txt'), prompt);
