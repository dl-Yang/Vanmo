const fs = require('fs');
const batches = JSON.parse(fs.readFileSync('/Users/yingu/Vanmo/.understand-anything/intermediate/batches.json', 'utf8'));
const scanResult = JSON.parse(fs.readFileSync('/Users/yingu/Vanmo/.understand-anything/intermediate/scan-result.json', 'utf8'));

batches.batches.forEach((batch, i) => {
  const prompt = `Analyze these files and produce GraphNode and GraphEdge objects.
Project root: /Users/yingu/Vanmo
Project: ${scanResult.projectName}
Languages: ${scanResult.languages.join(', ')}
Batch: ${i + 1}/${batches.totalBatches}
Skill directory (for bundled scripts): /Users/yingu/.understand-anything-plugin
Output: write to /Users/yingu/Vanmo/.understand-anything/intermediate/batch-${batch.batchIndex}.json (single-file mode) OR batch-${batch.batchIndex}-part-<k>.json (split mode, per Step B of your output protocol).

> **Language directive**: Generate all textual content (summaries, descriptions, tags, titles, languageNotes, languageLesson) in **zh**. Maintain technical accuracy while using natural, native-level phrasing in the target language. Keep technical terms in English when no standard translation exists (e.g., "middleware", "hook", "barrel").

Pre-resolved import data for this batch (use directly — do NOT re-resolve imports from source):
${JSON.stringify(batch.batchImportData, null, 2)}

Cross-batch neighbors with their exported symbols (confidence boost for cross-batch edges):
${JSON.stringify(batch.neighborMap, null, 2)}

Files to analyze in this batch (every entry MUST be passed through to batchFiles with all four fields — path, language, sizeLines, fileCategory):
${batch.files.map((f, j) => `${j + 1}. ${f.path} (${f.sizeLines} lines, language: ${f.language}, fileCategory: ${f.fileCategory})`).join('\n')}
`;
  fs.writeFileSync(`/Users/yingu/Vanmo/.understand-anything/tmp/prompt-${batch.batchIndex}.txt`, prompt);
});
