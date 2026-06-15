const fs = require('fs');

const inputPath = process.argv[2];
const outputPath = process.argv[3];

if (!inputPath || !outputPath) {
  console.error('Usage: node ua-tour-analyze.js <input-txt> <output-json>');
  process.exit(1);
}

try {
  const fileContent = fs.readFileSync(inputPath, 'utf-8');

  // Extract JSON blocks
  const extractJson = (content, marker) => {
    const idx = content.indexOf(marker);
    if (idx === -1) return [];
    const codeBlockStart = content.indexOf('```json\n', idx);
    if (codeBlockStart === -1) return [];
    const jsonStart = codeBlockStart + 8;
    const jsonEnd = content.indexOf('```', jsonStart);
    if (jsonEnd === -1) return [];
    const jsonStr = content.substring(jsonStart, jsonEnd);
    return JSON.parse(jsonStr);
  };

  const nodes = extractJson(fileContent, 'Nodes (all file-level nodes');
  const edges = extractJson(fileContent, 'Edges (all types');
  const layers = extractJson(fileContent, 'Layers:');

  const graph = { nodes, edges, layers };

  const fanIn = new Map();
  const fanOut = new Map();
  const nodeIndex = new Map();

  nodes.forEach(n => {
    fanIn.set(n.id, 0);
    fanOut.set(n.id, 0);
    nodeIndex.set(n.id, n);
  });

  edges.forEach(e => {
    if (fanOut.has(e.source)) fanOut.set(e.source, fanOut.get(e.source) + 1);
    if (fanIn.has(e.target)) fanIn.set(e.target, fanIn.get(e.target) + 1);
  });

  // A. Fan-In Ranking
  const fanInRanking = Array.from(fanIn.entries())
    .map(([id, count]) => ({ id, fanIn: count, name: nodeIndex.get(id)?.name || id }))
    .sort((a, b) => b.fanIn - a.fanIn)
    .slice(0, 20);

  // B. Fan-Out Ranking
  const fanOutRanking = Array.from(fanOut.entries())
    .map(([id, count]) => ({ id, fanOut: count, name: nodeIndex.get(id)?.name || id }))
    .sort((a, b) => b.fanOut - a.fanOut)
    .slice(0, 20);

  const fanOutThreshold = fanOutRanking.length > 0 ? (fanOutRanking[Math.floor(nodes.length * 0.1)]?.fanOut || 1) : 1;
  
  const fanInSorted = Array.from(fanIn.values()).sort((a, b) => a - b);
  const fanInThreshold = fanInSorted[Math.floor(fanInSorted.length * 0.25)] || 0;

  // C. Entry Point Candidates
  const entryPointCandidates = [];
  const entryRegex = /^(index|main|app|server|mod|manage|run|__main__|Application|Main|Program|config|App|VanmoApp)\.(ts|js|rs|go|py|java|cs|ru|php|swift|kt|cpp|c)$/i;

  nodes.forEach(n => {
    if (n.type === 'document') {
      if (n.filePath === 'README.md' || n.name === 'README.md') {
        entryPointCandidates.push({ id: n.id, score: 5, name: n.name, summary: n.summary });
      } else if (n.name.endsWith('.md') && (!n.filePath || !n.filePath.includes('/'))) {
        entryPointCandidates.push({ id: n.id, score: 2, name: n.name, summary: n.summary });
      }
    } else {
      let score = 0;
      if (entryRegex.test(n.name)) score += 3;
      const parts = (n.filePath || n.name).split('/');
      if (parts.length <= 2) score += 1;
      if (fanOut.get(n.id) >= fanOutThreshold) score += 1;
      if (fanIn.get(n.id) <= fanInThreshold) score += 1;
      
      if (score > 0) {
        entryPointCandidates.push({ id: n.id, score, name: n.name, summary: n.summary });
      }
    }
  });

  entryPointCandidates.sort((a, b) => b.score - a.score);

  // D. BFS Traversal
  const codeEntry = entryPointCandidates.find(c => nodeIndex.get(c.id)?.type !== 'document');
  const bfsTraversal = {
    startNode: codeEntry ? codeEntry.id : null,
    order: [],
    depthMap: {},
    byDepth: {}
  };

  if (codeEntry) {
    const queue = [{ id: codeEntry.id, depth: 0 }];
    const visited = new Set([codeEntry.id]);

    const forwardEdges = new Map();
    edges.forEach(e => {
      // follow imports, calls, exports, implements, instantiates, depends_on
      if (['imports', 'calls', 'exports', 'implements', 'instantiates', 'depends_on'].includes(e.type)) {
        if (!forwardEdges.has(e.source)) forwardEdges.set(e.source, []);
        forwardEdges.get(e.source).push(e.target);
      }
    });

    while (queue.length > 0) {
      const { id, depth } = queue.shift();
      bfsTraversal.order.push(id);
      bfsTraversal.depthMap[id] = depth;
      
      if (!bfsTraversal.byDepth[depth]) bfsTraversal.byDepth[depth] = [];
      bfsTraversal.byDepth[depth].push(id);

      const neighbors = forwardEdges.get(id) || [];
      neighbors.forEach(neighbor => {
        if (!visited.has(neighbor)) {
          visited.add(neighbor);
          queue.push({ id: neighbor, depth: depth + 1 });
        }
      });
    }
  }

  // E. Non-Code File Inventory
  const nonCodeFiles = { documentation: [], infrastructure: [], data: [], config: [] };
  nodes.forEach(n => {
    const item = { id: n.id, name: n.name, type: n.type, summary: n.summary };
    if (n.type === 'document') nonCodeFiles.documentation.push(item);
    else if (['service', 'pipeline', 'resource'].includes(n.type)) nonCodeFiles.infrastructure.push(item);
    else if (['table', 'schema', 'endpoint'].includes(n.type)) nonCodeFiles.data.push(item);
    else if (n.type === 'config') nonCodeFiles.config.push(item);
  });

  // F. Clusters
  const mutualEdges = new Map();
  edges.forEach(e => {
    if (['imports', 'calls', 'exports', 'implements', 'instantiates', 'depends_on'].includes(e.type)) {
      const key = `${e.source}->${e.target}`;
      mutualEdges.set(key, true);
    }
  });

  const clusters = [];

  nodes.forEach(n1 => {
    nodes.forEach(n2 => {
      if (n1.id !== n2.id) {
        if (mutualEdges.has(`${n1.id}->${n2.id}`) && mutualEdges.has(`${n2.id}->${n1.id}`)) {
          let found = false;
          for (let c of clusters) {
            if (c.nodes.includes(n1.id) || c.nodes.includes(n2.id)) {
              if (!c.nodes.includes(n1.id)) c.nodes.push(n1.id);
              if (!c.nodes.includes(n2.id)) c.nodes.push(n2.id);
              c.edgeCount += 2;
              found = true;
              break;
            }
          }
          if (!found) {
            clusters.push({ nodes: [n1.id, n2.id], edgeCount: 2 });
          }
        }
      }
    });
  });

  // G. Layers
  const layersResult = {
    count: layers.length,
    list: layers.map(l => ({ id: l.id, name: l.name, description: l.description }))
  };

  // H. Node Summary Index
  const nodeSummaryIndex = {};
  nodes.forEach(n => {
    nodeSummaryIndex[n.id] = { name: n.name, type: n.type, summary: n.summary };
  });

  const output = {
    scriptCompleted: true,
    entryPointCandidates: entryPointCandidates.slice(0, 5),
    fanInRanking,
    fanOutRanking,
    bfsTraversal,
    nonCodeFiles,
    clusters: clusters.slice(0, 10),
    layers: layersResult,
    nodeSummaryIndex,
    totalNodes: nodes.length,
    totalEdges: edges.length
  };

  fs.writeFileSync(outputPath, JSON.stringify(output, null, 2));
  process.exit(0);

} catch (err) {
  console.error(err);
  process.exit(1);
}