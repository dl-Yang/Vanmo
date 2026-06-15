const fs = require('fs');

const projRoot = '/Users/yingu/Vanmo';
const scanResult = JSON.parse(fs.readFileSync(`${projRoot}/.understand-anything/intermediate/scan-result.json`, 'utf8'));

let meta = {};
try {
  meta = JSON.parse(fs.readFileSync(`${projRoot}/.understand-anything/meta.json`, 'utf8'));
} catch(e) {
  meta.gitCommitHash = "1c18734d98602fb1201ca0f6ce1a82d36331794f";
}

const input = {
  projectRoot: projRoot,
  sourceFilePaths: scanResult.files.map(f => f.path),
  gitCommitHash: meta.gitCommitHash
};

fs.writeFileSync(`${projRoot}/.understand-anything/intermediate/fingerprint-input.json`, JSON.stringify(input, null, 2));
