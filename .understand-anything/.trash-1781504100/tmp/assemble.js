const fs = require('fs');

const projRoot = '/Users/yingu/Vanmo';

const scanResult = JSON.parse(fs.readFileSync(`${projRoot}/.understand-anything/intermediate/scan-result.json`, 'utf8'));
const assembledGraph = JSON.parse(fs.readFileSync(`${projRoot}/.understand-anything/intermediate/assembled-graph.json`, 'utf8'));
const layers = JSON.parse(fs.readFileSync(`${projRoot}/.understand-anything/intermediate/layers.json`, 'utf8'));
let tour = [];
try {
  const t = JSON.parse(fs.readFileSync(`${projRoot}/.understand-anything/intermediate/tour.json`, 'utf8'));
  tour = t.steps || t;
} catch(e) {}

let meta = {};
try {
  meta = JSON.parse(fs.readFileSync(`${projRoot}/.understand-anything/meta.json`, 'utf8'));
} catch(e) {
  meta.gitCommitHash = "1c18734d98602fb1201ca0f6ce1a82d36331794f";
}

const finalGraph = {
  version: "1.0.0",
  project: {
    name: scanResult.projectName,
    languages: scanResult.languages,
    frameworks: scanResult.frameworks,
    description: scanResult.projectDescription,
    analyzedAt: new Date().toISOString(),
    gitCommitHash: meta.gitCommitHash
  },
  nodes: assembledGraph.nodes,
  edges: assembledGraph.edges,
  layers: layers.layers || layers,
  tour: tour
};

fs.writeFileSync(`${projRoot}/.understand-anything/intermediate/assembled-graph-final.json`, JSON.stringify(finalGraph, null, 2));
