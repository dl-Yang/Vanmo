#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const FILE_LEVEL_TYPES = new Set([
  'file',
  'config',
  'document',
  'service',
  'pipeline',
  'table',
  'schema',
  'resource',
  'endpoint',
]);

function fatal(message) {
  console.error(message);
  process.exit(1);
}

const [inputPath, outputPath] = process.argv.slice(2);
if (!inputPath || !outputPath) {
  fatal('Usage: ua-arch-analyze.js <input.json> <output.json>');
}

let input;
try {
  input = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
} catch (error) {
  fatal(`Failed to read input JSON: ${error.message}`);
}

const fileNodes = input.fileNodes || (input.nodes || []).filter((node) => FILE_LEVEL_TYPES.has(node.type));
const nodeById = new Map(fileNodes.map((node) => [node.id, node]));
const fileNodeIds = new Set(fileNodes.map((node) => node.id));
const rawEdges = input.allEdges || input.edges || [];
const allEdges = rawEdges.filter((edge) => fileNodeIds.has(edge.source) && fileNodeIds.has(edge.target));
const importEdges = (input.importEdges || allEdges).filter((edge) => {
  const type = String(edge.type || '').toLowerCase();
  return fileNodeIds.has(edge.source) && fileNodeIds.has(edge.target) && (type === 'imports' || type === 'import');
});

function normalizePath(filePath) {
  return String(filePath || '').replace(/^\/+/, '').replace(/\\/g, '/');
}

function commonDirectoryPrefix(paths) {
  const splitPaths = paths.map((filePath) => normalizePath(filePath).split('/').filter(Boolean));
  if (splitPaths.length === 0) return [];
  const prefix = [];
  for (let i = 0; ; i += 1) {
    const segment = splitPaths[0][i];
    if (!segment || splitPaths.some((parts) => parts[i] !== segment)) break;
    prefix.push(segment);
  }
  return prefix;
}

const filePaths = fileNodes.map((node) => normalizePath(node.filePath || node.name || node.id));
const prefix = commonDirectoryPrefix(filePaths);
const hasUsefulPrefix = prefix.length > 0 && filePaths.every((filePath) => filePath.split('/').length > prefix.length);
const directoryGroups = {};
const groupById = {};

function extensionGroup(filePath) {
  const base = path.posix.basename(filePath);
  if (/\.(test|spec)\./.test(base)) return 'test';
  if (/\.(config|yml|yaml|plist|xcconfig)$/.test(base)) return 'config';
  if (/\.(md|rst)$/.test(base)) return 'documentation';
  return path.posix.extname(base).replace('.', '') || 'root';
}

for (const node of fileNodes) {
  const filePath = normalizePath(node.filePath || node.name || node.id);
  const parts = filePath.split('/').filter(Boolean);
  let group;
  if (hasUsefulPrefix) {
    group = parts[prefix.length] || 'root';
  } else if (parts.length > 1) {
    group = parts[0];
  } else {
    group = extensionGroup(filePath);
  }
  directoryGroups[group] ||= [];
  directoryGroups[group].push(node.id);
  groupById[node.id] = group;
}

const nodeTypeGroups = {};
for (const node of fileNodes) {
  nodeTypeGroups[node.type] ||= [];
  nodeTypeGroups[node.type].push(node.id);
}

const fanIn = Object.fromEntries(fileNodes.map((node) => [node.id, 0]));
const fanOut = Object.fromEntries(fileNodes.map((node) => [node.id, 0]));
const interGroupCounts = new Map();
const groupImportsFrom = {};
const groupImportedBy = {};
const intra = {};

for (const group of Object.keys(directoryGroups)) {
  groupImportsFrom[group] = new Set();
  groupImportedBy[group] = new Set();
  intra[group] = { internalEdges: 0, totalEdges: 0 };
}

for (const edge of importEdges) {
  fanOut[edge.source] = (fanOut[edge.source] || 0) + 1;
  fanIn[edge.target] = (fanIn[edge.target] || 0) + 1;
  const fromGroup = groupById[edge.source] || 'root';
  const toGroup = groupById[edge.target] || 'root';
  intra[fromGroup].totalEdges += 1;
  if (toGroup !== fromGroup) intra[toGroup].totalEdges += 1;
  if (fromGroup === toGroup) {
    intra[fromGroup].internalEdges += 1;
  } else {
    groupImportsFrom[fromGroup].add(toGroup);
    groupImportedBy[toGroup].add(fromGroup);
    const key = `${fromGroup}\u0000${toGroup}`;
    interGroupCounts.set(key, (interGroupCounts.get(key) || 0) + 1);
  }
}

const interGroupImports = [...interGroupCounts.entries()].map(([key, count]) => {
  const [from, to] = key.split('\u0000');
  return { from, to, count };
}).sort((a, b) => b.count - a.count || a.from.localeCompare(b.from) || a.to.localeCompare(b.to));

const intraGroupDensity = Object.fromEntries(Object.entries(intra).map(([group, value]) => [
  group,
  {
    ...value,
    density: value.totalEdges ? Number((value.internalEdges / value.totalEdges).toFixed(3)) : 0,
  },
]));

const crossKeyCounts = new Map();
for (const edge of allEdges) {
  const from = nodeById.get(edge.source);
  const to = nodeById.get(edge.target);
  const key = `${from.type}\u0000${to.type}\u0000${edge.type || 'related'}`;
  crossKeyCounts.set(key, (crossKeyCounts.get(key) || 0) + 1);
}
const crossCategoryEdges = [...crossKeyCounts.entries()].map(([key, count]) => {
  const [fromType, toType, edgeType] = key.split('\u0000');
  return { fromType, toType, edgeType, count };
}).sort((a, b) => b.count - a.count);

function matchPattern(group, ids) {
  const lower = group.toLowerCase();
  const paths = ids.map((id) => normalizePath(nodeById.get(id)?.filePath || ''));
  if (/^(routes|api|controllers|endpoints|handlers|serializers|controller|routers|blueprints)$/.test(lower)) return 'api';
  if (/^(services|core|lib|domain|logic|internal|composables|mailers|jobs|channels|signals)$/.test(lower)) return 'service';
  if (/^(models|db|data|persistence|repository|entities|entity|database|schema|sql|migrations)$/.test(lower)) return 'data';
  if (/^(components|views|pages|ui|layouts|screens)$/.test(lower)) return 'ui';
  if (/^(utils|helpers|common|shared|tools|pkg|templatetags)$/.test(lower)) return 'utility';
  if (/^(config|constants|env|settings)$/.test(lower)) return 'config';
  if (/^(__tests__|test|tests|spec|specs)$/.test(lower)) return 'test';
  if (/^(types|interfaces|schemas|contracts|dtos|dto|request|response)$/.test(lower)) return 'types';
  if (/^(store|state|reducers|actions|slices)$/.test(lower)) return 'state';
  if (/^(assets|static|public)$/.test(lower)) return 'assets';
  if (/^(docs|documentation|wiki)$/.test(lower)) return 'documentation';
  if (/^(\.github|\.gitlab|\.circleci)$/.test(lower)) return 'ci-cd';
  if (/^(deploy|deployment|infra|infrastructure|docker|k8s|kubernetes|helm|charts|terraform|tf)$/.test(lower)) return 'infrastructure';
  if (paths.every((filePath) => /\.(md|rst)$/.test(filePath))) return 'documentation';
  if (paths.every((filePath) => /\.(test|spec)\.|Tests?\.swift$/.test(filePath))) return 'test';
  return 'unknown';
}

const patternMatches = Object.fromEntries(Object.entries(directoryGroups).map(([group, ids]) => [group, matchPattern(group, ids)]));

const infraFiles = fileNodes
  .filter((node) => {
    const filePath = normalizePath(node.filePath || '');
    return node.type === 'service' || node.type === 'pipeline' || /(^|\/)(Dockerfile|docker-compose|Makefile)|\.tf(vars)?$|\.github\/workflows|\.gitlab-ci|Jenkinsfile/.test(filePath);
  })
  .map((node) => normalizePath(node.filePath));

const deploymentTopology = {
  hasDockerfile: infraFiles.some((filePath) => /(^|\/)Dockerfile/.test(filePath)),
  hasCompose: infraFiles.some((filePath) => /docker-compose/.test(filePath)),
  hasK8s: infraFiles.some((filePath) => /(k8s|kubernetes|helm|charts)/.test(filePath)),
  hasTerraform: infraFiles.some((filePath) => /\.tf(vars)?$/.test(filePath)),
  hasCI: infraFiles.some((filePath) => /(\.github\/workflows|\.gitlab-ci|Jenkinsfile)/.test(filePath)),
  infraFiles,
};

const dataPipeline = {
  schemaFiles: fileNodes.filter((node) => node.type === 'schema' || /\.(graphql|gql|proto|prisma)$/.test(normalizePath(node.filePath || ''))).map((node) => node.filePath),
  migrationFiles: fileNodes.filter((node) => /migrations?\/.*\.(sql|swift|js|ts)$/i.test(normalizePath(node.filePath || ''))).map((node) => node.filePath),
  dataModelFiles: fileNodes.filter((node) => /model|entity|dto/i.test(`${node.filePath} ${(node.tags || []).join(' ')}`)).map((node) => node.filePath),
  apiHandlerFiles: fileNodes.filter((node) => /api|endpoint|route|controller/i.test(`${node.filePath} ${(node.tags || []).join(' ')}`)).map((node) => node.filePath),
};

const groupsWithDocs = Object.entries(directoryGroups).filter(([, ids]) => ids.some((id) => nodeById.get(id)?.type === 'document')).map(([group]) => group);
const docCoverage = {
  groupsWithDocs: groupsWithDocs.length,
  totalGroups: Object.keys(directoryGroups).length,
  coverageRatio: Object.keys(directoryGroups).length ? Number((groupsWithDocs.length / Object.keys(directoryGroups).length).toFixed(3)) : 0,
  undocumentedGroups: Object.keys(directoryGroups).filter((group) => !groupsWithDocs.includes(group)),
};

const dependencyDirection = [];
const pairKeys = new Set();
for (const { from, to } of interGroupImports) {
  pairKeys.add([from, to].sort().join('\u0000'));
}
for (const pairKey of pairKeys) {
  const [a, b] = pairKey.split('\u0000');
  const ab = interGroupCounts.get(`${a}\u0000${b}`) || 0;
  const ba = interGroupCounts.get(`${b}\u0000${a}`) || 0;
  if (ab > ba) dependencyDirection.push({ dependent: a, dependsOn: b });
  if (ba > ab) dependencyDirection.push({ dependent: b, dependsOn: a });
}

const result = {
  scriptCompleted: true,
  directoryGroups,
  nodeTypeGroups,
  crossCategoryEdges,
  interGroupImports,
  intraGroupDensity,
  patternMatches,
  deploymentTopology,
  dataPipeline,
  docCoverage,
  dependencyDirection,
  fileStats: {
    totalFileNodes: fileNodes.length,
    filesPerGroup: Object.fromEntries(Object.entries(directoryGroups).map(([group, ids]) => [group, ids.length])),
    nodeTypeCounts: Object.fromEntries(Object.entries(nodeTypeGroups).map(([type, ids]) => [type, ids.length])),
  },
  fileFanIn: fanIn,
  fileFanOut: fanOut,
};

fs.writeFileSync(outputPath, `${JSON.stringify(result, null, 2)}\n`);
