const fs = require('fs');
const changedFiles = fs.readFileSync('/Users/yingu/Vanmo/.understand-anything/tmp/changed-files.txt', 'utf8').split('\n').filter(Boolean);
const changedSet = new Set(changedFiles);

const graph = JSON.parse(fs.readFileSync('/Users/yingu/Vanmo/.understand-anything/knowledge-graph.json', 'utf8'));

const nodesToKeep = [];
const removedNodeIds = new Set();

graph.nodes.forEach(node => {
  if (node.filePath && changedSet.has(node.filePath)) {
    removedNodeIds.add(node.id);
  } else {
    nodesToKeep.push(node);
  }
});

const edgesToKeep = [];
graph.edges.forEach(edge => {
  if (removedNodeIds.has(edge.source) || removedNodeIds.has(edge.target)) {
    // remove
  } else {
    edgesToKeep.push(edge);
  }
});

fs.writeFileSync('/Users/yingu/Vanmo/.understand-anything/intermediate/batch-existing.json', JSON.stringify({
  nodes: nodesToKeep,
  edges: edgesToKeep
}));
