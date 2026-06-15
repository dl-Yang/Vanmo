const fs = require('fs');

const text = fs.readFileSync('/Users/yingu/Vanmo/.understand-anything/tmp/arch-prompt.txt', 'utf8');

function extractJson(headerRegex) {
    const match = text.match(headerRegex);
    if (!match) return null;
    const block = text.substring(match.index);
    const jsonMatch = block.match(/```json\n([\s\S]*?)\n```/);
    if (jsonMatch) {
        return JSON.parse(jsonMatch[1]);
    }
    return null;
}

const fileNodes = extractJson(/File nodes.*:/);
const importEdges = extractJson(/Import edges:/);
const allEdges = extractJson(/All edges.*:/);

// Previous layers
const previousLayersMatch = text.match(/Previous layer definitions[^:]*:\n```json\n([\s\S]*?)\n```/);
const previousLayers = previousLayersMatch ? JSON.parse(previousLayersMatch[1]) : [];

const input = {
    fileNodes: fileNodes || [],
    importEdges: importEdges || [],
    allEdges: allEdges || [],
    previousLayers: previousLayers || []
};

fs.writeFileSync('/Users/yingu/Vanmo/.understand-anything/tmp/ua-arch-input.json', JSON.stringify(input, null, 2));
console.log(`Parsed ${input.fileNodes.length} file nodes, ${input.importEdges.length} import edges, ${input.allEdges.length} all edges.`);
