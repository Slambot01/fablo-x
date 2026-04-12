#!/bin/bash
cd ~/lfdt-project/fablo-fork
node -e '
const s = require("./docs/schema.json");
console.log("required:", JSON.stringify(s.required, null, 2));
console.log("properties:", Object.keys(s.properties || {}));
const g = s.properties && s.properties.global;
if (g) console.log("global.required:", JSON.stringify(g.required, null, 2));
'
