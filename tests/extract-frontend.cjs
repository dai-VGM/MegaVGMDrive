// Mechanical extraction from the frozen v2.0 frontend, preserving method bodies.
// Used once for import; retained to make the source provenance reviewable.
const fs = require('fs');
const path = require('path');
const source = process.argv[2];
const target = path.resolve(__dirname, '../frontend/src/lib');
const api = fs.readFileSync(path.join(source, 'src/lib/api.ts'), 'utf8');
const validators = api.slice(api.indexOf('function isMegaVGMBrowseResponse'), api.indexOf('export class ControlApi'));
const methods = api.slice(api.indexOf('  async megaVGMStatus'), api.indexOf('  // games'));
const imports = api.slice(api.indexOf('  MegaVGMLifecycleResponse,'), api.indexOf('  Screenshot,'));
fs.writeFileSync(path.join(target, 'api.ts'), `import axios from "axios";\nimport {\n${imports}} from "./models";\n\n${validators}export class ControlApi {\n  constructor() {\n    axios.defaults.baseURL = window.location.origin + "/api";\n  }\n\n${methods}}\n`);
const queries = fs.readFileSync(path.join(source, 'src/lib/queries.ts'), 'utf8');
fs.writeFileSync(path.join(target, 'queries.ts'), 'import { useQuery } from "@tanstack/react-query";\nimport { ControlApi } from "./api";\nconst api = new ControlApi();\n\n' + queries.slice(queries.indexOf('export const useMegaVGMStatus'), queries.indexOf('export const useIndexedSystems')));
