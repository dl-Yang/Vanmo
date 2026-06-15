#!/usr/bin/env node

const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function isAllowedTourNode(node) {
  return ["file", "config", "document", "service", "pipeline", "table", "schema", "resource", "endpoint"].includes(node.type);
}

function main() {
  const [inputPath, outputPath] = process.argv.slice(2);
  if (!inputPath || !outputPath) {
    console.error("Usage: ua-tour-analyze.js <graph.json> <results.json>");
    process.exit(1);
  }

  const graph = readJson(inputPath);
  const layers = graph.layers || (process.env.UA_LAYERS_PATH ? readJson(process.env.UA_LAYERS_PATH) : []);
  const nodes = Array.isArray(graph.nodes) ? graph.nodes : [];
  const edges = Array.isArray(graph.edges) ? graph.edges : [];
  const nodeById = new Map(nodes.map((node) => [node.id, node]));
  const allowedNodes = nodes.filter(isAllowedTourNode);
  const allowedIds = new Set(allowedNodes.map((node) => node.id));

  const fanIn = new Map();
  const fanOut = new Map();
  for (const node of nodes) {
    fanIn.set(node.id, 0);
    fanOut.set(node.id, 0);
  }
  for (const edge of edges) {
    if (nodeById.has(edge.source)) fanOut.set(edge.source, (fanOut.get(edge.source) || 0) + 1);
    if (nodeById.has(edge.target)) fanIn.set(edge.target, (fanIn.get(edge.target) || 0) + 1);
  }

  const rank = (metricMap, metricName) =>
    allowedNodes
      .map((node) => ({ id: node.id, [metricName]: metricMap.get(node.id) || 0, name: node.name, summary: node.summary }))
      .sort((a, b) => b[metricName] - a[metricName] || a.id.localeCompare(b.id))
      .slice(0, 20);

  const fanInRanking = rank(fanIn, "fanIn");
  const fanOutRanking = rank(fanOut, "fanOut");
  const sortedFanOut = allowedNodes.map((node) => fanOut.get(node.id) || 0).sort((a, b) => a - b);
  const sortedFanIn = allowedNodes.map((node) => fanIn.get(node.id) || 0).sort((a, b) => a - b);
  const fanOutTopThreshold = sortedFanOut[Math.max(0, Math.floor(sortedFanOut.length * 0.9) - 1)] || 0;
  const fanInLowThreshold = sortedFanIn[Math.max(0, Math.floor(sortedFanIn.length * 0.25) - 1)] || 0;
  const entryPattern = /(^|\/)(index|main|app|server|manage|run|wsgi|asgi|__main__|Application|Main|Program|App)\.(ts|js|swift|kt|go|py|rs|java|cs|php|c|cpp)$/;

  const entryPointCandidates = allowedNodes
    .map((node) => {
      let score = 0;
      const path = node.filePath || node.name || "";
      const depth = path.split("/").length;
      if (node.type === "document" && path === "README.md") score += 5;
      if (node.type === "document" && path.endsWith(".md") && depth === 1) score += 2;
      if (node.type === "file") {
        if (entryPattern.test(path)) score += 3;
        if (depth <= 2) score += 1;
        if ((fanOut.get(node.id) || 0) >= fanOutTopThreshold) score += 1;
        if ((fanIn.get(node.id) || 0) <= fanInLowThreshold) score += 1;
      }
      return { id: node.id, score, name: node.name, summary: node.summary, type: node.type };
    })
    .filter((candidate) => candidate.score > 0)
    .sort((a, b) => b.score - a.score || a.id.localeCompare(b.id))
    .slice(0, 5);

  const topCodeEntry = entryPointCandidates.find((candidate) => nodeById.get(candidate.id)?.type === "file");
  const traversalEdges = edges.filter((edge) => ["imports", "calls"].includes(edge.type));
  const outgoing = new Map();
  for (const edge of traversalEdges) {
    if (!outgoing.has(edge.source)) outgoing.set(edge.source, []);
    outgoing.get(edge.source).push(edge.target);
  }

  const bfsTraversal = { startNode: topCodeEntry?.id || null, order: [], depthMap: {}, byDepth: {} };
  if (topCodeEntry) {
    const queue = [{ id: topCodeEntry.id, depth: 0 }];
    const seen = new Set([topCodeEntry.id]);
    while (queue.length > 0) {
      const current = queue.shift();
      bfsTraversal.order.push(current.id);
      bfsTraversal.depthMap[current.id] = current.depth;
      if (!bfsTraversal.byDepth[current.depth]) bfsTraversal.byDepth[current.depth] = [];
      bfsTraversal.byDepth[current.depth].push(current.id);
      for (const next of outgoing.get(current.id) || []) {
        if (!seen.has(next) && allowedIds.has(next)) {
          seen.add(next);
          queue.push({ id: next, depth: current.depth + 1 });
        }
      }
    }
  }

  const nonCodeFiles = { documentation: [], infrastructure: [], data: [], config: [] };
  for (const node of allowedNodes) {
    const item = { id: node.id, name: node.name, type: node.type, summary: node.summary };
    if (node.type === "document") nonCodeFiles.documentation.push(item);
    if (["service", "pipeline", "resource"].includes(node.type)) nonCodeFiles.infrastructure.push(item);
    if (["table", "schema", "endpoint"].includes(node.type)) nonCodeFiles.data.push(item);
    if (node.type === "config") nonCodeFiles.config.push(item);
  }

  const edgeKey = new Set(edges.map((edge) => `${edge.source}\u0000${edge.target}\u0000${edge.type}`));
  const clusters = [];
  for (const edge of edges) {
    if (!["imports", "calls"].includes(edge.type) || !allowedIds.has(edge.source) || !allowedIds.has(edge.target)) continue;
    if (edgeKey.has(`${edge.target}\u0000${edge.source}\u0000${edge.type}`)) {
      const pair = [edge.source, edge.target].sort();
      if (!clusters.some((cluster) => cluster.nodes[0] === pair[0] && cluster.nodes[1] === pair[1])) {
        clusters.push({ nodes: pair, edgeCount: 2 });
      }
    }
  }

  const nodeSummaryIndex = {};
  for (const node of allowedNodes) {
    nodeSummaryIndex[node.id] = { name: node.name, type: node.type, summary: node.summary };
  }

  fs.writeFileSync(
    outputPath,
    JSON.stringify(
      {
        scriptCompleted: true,
        entryPointCandidates,
        fanInRanking,
        fanOutRanking,
        bfsTraversal,
        nonCodeFiles,
        clusters: clusters.slice(0, 10),
        layers: { count: layers.length, list: layers.map(({ id, name, description }) => ({ id, name, description })) },
        nodeSummaryIndex,
        totalNodes: nodes.length,
        totalEdges: edges.length,
      },
      null,
      2
    )
  );
}

try {
  main();
} catch (error) {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
}
