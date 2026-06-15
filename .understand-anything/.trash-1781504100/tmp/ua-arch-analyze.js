const fs = require('fs');
const path = require('path');

const inputPath = process.argv[2];
const outputPath = process.argv[3];

if (!inputPath || !outputPath) {
    console.error("Usage: node ua-arch-analyze.js <input.json> <output.json>");
    process.exit(1);
}

const input = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
const fileNodes = input.fileNodes || [];
const allEdgesRaw = input.allEdges || [];

// Create valid node ID set
const validNodeIds = new Set(fileNodes.map(n => n.id));

// Filter edges to only those between file nodes
const allEdges = allEdgesRaw.filter(e => validNodeIds.has(e.source) && validNodeIds.has(e.target));

// Treat 'depends_on', 'calls', 'references' as import edges for structural code analysis
const importEdges = allEdges.filter(e => ['depends_on', 'calls', 'references', 'imports'].includes(e.type));

// A. Directory Grouping
function getCommonPrefix(paths) {
    if (paths.length === 0) return '';
    const splitPaths = paths.map(p => p.split('/'));
    let common = [];
    for (let i = 0; i < splitPaths[0].length - 1; i++) { // -1 to ignore file names
        const part = splitPaths[0][i];
        if (splitPaths.every(sp => sp[i] === part)) {
            common.push(part);
        } else {
            break;
        }
    }
    return common.length > 0 ? common.join('/') + '/' : '';
}

const filePaths = fileNodes.map(n => n.filePath);
const commonPrefix = getCommonPrefix(filePaths);

const directoryGroups = {};
for (const node of fileNodes) {
    let group = '';
    const relativePath = node.filePath.startsWith(commonPrefix) ? node.filePath.substring(commonPrefix.length) : node.filePath;
    const parts = relativePath.split('/');
    if (parts.length > 1) {
        group = parts[0];
    } else {
        // Flat structure grouping
        if (node.filePath.match(/\.(test|spec)\./)) group = 'test';
        else if (node.type === 'config' || node.filePath.match(/\.config\./)) group = 'config';
        else if (node.type === 'document') group = 'document';
        else group = 'root';
    }
    
    if (!directoryGroups[group]) directoryGroups[group] = [];
    directoryGroups[group].push(node.id);
}

// B. Node Type Grouping
const nodeTypeGroups = {};
for (const node of fileNodes) {
    if (!nodeTypeGroups[node.type]) nodeTypeGroups[node.type] = [];
    nodeTypeGroups[node.type].push(node.id);
}

// Map Node ID to its Directory Group
const nodeToGroup = {};
for (const [group, nodes] of Object.entries(directoryGroups)) {
    for (const id of nodes) {
        nodeToGroup[id] = group;
    }
}

const nodeToType = {};
for (const node of fileNodes) {
    nodeToType[node.id] = node.type;
}

// C. Import Adjacency Matrix
const fileFanIn = {};
const fileFanOut = {};
for (const node of fileNodes) {
    fileFanIn[node.id] = 0;
    fileFanOut[node.id] = 0;
}

for (const edge of importEdges) {
    fileFanOut[edge.source] = (fileFanOut[edge.source] || 0) + 1;
    fileFanIn[edge.target] = (fileFanIn[edge.target] || 0) + 1;
}

// D. Cross-Category Dependency Analysis
const crossCategoryEdgesCount = {};
for (const edge of allEdges) {
    const fromType = nodeToType[edge.source];
    const toType = nodeToType[edge.target];
    if (fromType !== toType) {
        const key = `${fromType}->${toType}:${edge.type}`;
        crossCategoryEdgesCount[key] = (crossCategoryEdgesCount[key] || 0) + 1;
    }
}
const crossCategoryEdges = Object.entries(crossCategoryEdgesCount).map(([key, count]) => {
    const [types, edgeType] = key.split(':');
    const [fromType, toType] = types.split('->');
    return { fromType, toType, edgeType, count };
});

// E. Inter-Group Import Frequency
const interGroupCounts = {};
for (const edge of importEdges) {
    const sourceGroup = nodeToGroup[edge.source];
    const targetGroup = nodeToGroup[edge.target];
    if (sourceGroup !== targetGroup && sourceGroup && targetGroup) {
        const key = `${sourceGroup}->${targetGroup}`;
        interGroupCounts[key] = (interGroupCounts[key] || 0) + 1;
    }
}
const interGroupImports = Object.entries(interGroupCounts).map(([key, count]) => {
    const [from, to] = key.split('->');
    return { from, to, count };
});

// F. Intra-Group Import Density
const groupEdges = {};
for (const group of Object.keys(directoryGroups)) {
    groupEdges[group] = { internal: 0, total: 0 };
}
for (const edge of importEdges) {
    const sourceGroup = nodeToGroup[edge.source];
    const targetGroup = nodeToGroup[edge.target];
    if (sourceGroup) groupEdges[sourceGroup].total++;
    if (targetGroup && sourceGroup !== targetGroup) groupEdges[targetGroup].total++;
    
    if (sourceGroup === targetGroup && sourceGroup) {
        groupEdges[sourceGroup].internal++;
    }
}
const intraGroupDensity = {};
for (const [group, counts] of Object.entries(groupEdges)) {
    intraGroupDensity[group] = {
        internalEdges: counts.internal,
        totalEdges: counts.total,
        density: counts.total > 0 ? counts.internal / counts.total : 0
    };
}

// G. Directory Pattern Matching
const patternMatches = {};
for (const group of Object.keys(directoryGroups)) {
    let lowerGroup = group.toLowerCase();
    if (['routes', 'api', 'controllers', 'endpoints', 'handlers', 'routers', 'blueprints', 'serializers'].includes(lowerGroup)) patternMatches[group] = 'api';
    else if (['services', 'core', 'lib', 'domain', 'logic', 'signals', 'internal', 'composables', 'mailers', 'jobs', 'channels', 'src/main/java'].includes(lowerGroup)) patternMatches[group] = 'service';
    else if (['models', 'db', 'data', 'persistence', 'repository', 'entities', 'migrations', 'sql', 'database', 'schema', 'entity'].includes(lowerGroup)) patternMatches[group] = 'data';
    else if (['components', 'views', 'pages', 'ui', 'layouts', 'screens'].includes(lowerGroup)) patternMatches[group] = 'ui';
    else if (['middleware', 'plugins', 'interceptors', 'guards'].includes(lowerGroup)) patternMatches[group] = 'middleware';
    else if (['utils', 'helpers', 'common', 'shared', 'tools', 'templatetags', 'pkg'].includes(lowerGroup)) patternMatches[group] = 'utility';
    else if (['config', 'constants', 'env', 'settings', 'management', 'commands'].includes(lowerGroup)) patternMatches[group] = 'config';
    else if (['__tests__', 'test', 'tests', 'spec', 'specs', 'src/test/java'].includes(lowerGroup)) patternMatches[group] = 'test';
    else if (['types', 'interfaces', 'schemas', 'contracts', 'dtos', 'dto', 'request', 'response'].includes(lowerGroup)) patternMatches[group] = 'types';
    else if (['hooks'].includes(lowerGroup)) patternMatches[group] = 'hooks';
    else if (['store', 'state', 'reducers', 'actions', 'slices'].includes(lowerGroup)) patternMatches[group] = 'state';
    else if (['assets', 'static', 'public'].includes(lowerGroup)) patternMatches[group] = 'assets';
    else if (['cmd', 'bin'].includes(lowerGroup)) patternMatches[group] = 'entry';
    else if (['docs', 'documentation', 'wiki'].includes(lowerGroup)) patternMatches[group] = 'documentation';
    else if (['deploy', 'deployment', 'infra', 'infrastructure', 'k8s', 'kubernetes', 'helm', 'charts', 'terraform', 'tf', 'docker'].includes(lowerGroup)) patternMatches[group] = 'infrastructure';
    else if (['.github', '.gitlab', '.circleci'].includes(lowerGroup)) patternMatches[group] = 'ci-cd';
}

// Extract some file stats
const filesPerGroup = {};
for (const [group, nodes] of Object.entries(directoryGroups)) {
    filesPerGroup[group] = nodes.length;
}
const nodeTypeCounts = {};
for (const [type, nodes] of Object.entries(nodeTypeGroups)) {
    nodeTypeCounts[type] = nodes.length;
}

const fileStats = {
    totalFileNodes: fileNodes.length,
    filesPerGroup,
    nodeTypeCounts
};

// Simplified topologies for quick checks
const deploymentTopology = {
    hasDockerfile: fileNodes.some(n => n.filePath.toLowerCase().includes('dockerfile')),
    hasCompose: fileNodes.some(n => n.filePath.toLowerCase().includes('docker-compose')),
    hasK8s: false, // simplified
    hasTerraform: false, // simplified
    hasCI: fileNodes.some(n => n.filePath.includes('.github/') || n.filePath.includes('.gitlab')),
    infraFiles: fileNodes.filter(n => n.type === 'service' || n.type === 'pipeline').map(n => n.filePath)
};

const dataPipeline = {
    schemaFiles: fileNodes.filter(n => n.type === 'schema').map(n => n.filePath),
    migrationFiles: fileNodes.filter(n => n.filePath.includes('migrations/')).map(n => n.filePath),
    dataModelFiles: fileNodes.filter(n => n.filePath.includes('models/')).map(n => n.filePath),
    apiHandlerFiles: fileNodes.filter(n => n.filePath.includes('routes/')).map(n => n.filePath)
};

const docGroups = new Set();
for (const node of fileNodes) {
    if (node.type === 'document') {
        const group = nodeToGroup[node.id];
        if (group) docGroups.add(group);
    }
}
const totalGroups = Object.keys(directoryGroups).length;
const docCoverage = {
    groupsWithDocs: docGroups.size,
    totalGroups: totalGroups,
    coverageRatio: totalGroups > 0 ? docGroups.size / totalGroups : 0,
    undocumentedGroups: Object.keys(directoryGroups).filter(g => !docGroups.has(g))
};

// K. Dependency Direction
const dependencyDirection = [];
const groupPairDeps = {};
for (const imp of interGroupImports) {
    const { from, to, count } = imp;
    const pair = [from, to].sort().join('|');
    if (!groupPairDeps[pair]) groupPairDeps[pair] = { [from]: 0, [to]: 0 };
    groupPairDeps[pair][from] = count;
}
for (const [pair, counts] of Object.entries(groupPairDeps)) {
    const [a, b] = pair.split('|');
    if (counts[a] > (counts[b] || 0)) {
        dependencyDirection.push({ dependent: a, dependsOn: b });
    } else if (counts[b] > (counts[a] || 0)) {
        dependencyDirection.push({ dependent: b, dependsOn: a });
    }
}

const output = {
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
    fileStats,
    fileFanIn,
    fileFanOut
};

fs.writeFileSync(outputPath, JSON.stringify(output, null, 2));
console.log("Analysis complete.");
