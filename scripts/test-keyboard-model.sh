#!/usr/bin/env bash
# Node unit test of the keyboard widget's layout names (needs node; the widget itself does not).
set -euo pipefail
cd "$(dirname "$0")/../plugins/orbital.keyboard"
node -e '
const M = require("./KeyboardModel.js"), eq = (a, b) => { if (a !== b) { console.log("FAIL -", a, "!=", b); process.exit(1) } };
eq(M.variantLabel("br", ""), "ABNT2"); eq(M.variantLabel("br", "abnt2"), "ABNT2");
eq(M.variantLabel("br", "nodeadkeys"), "No dead keys"); eq(M.variantLabel("us", ""), "QWERTY");
eq(M.variantLabel("us", "intl"), "Intl"); eq(M.variantLabel("de", ""), "Standard");
eq(M.languageName("br", "Portuguese (Brazil)"), "Portuguese (BR)");
eq(M.languageName("us", "English (US)"), "English (US)");
eq(M.languageName("epo", "Esperanto"), "Esperanto (EPO)");
eq(M.languageName("xx", "xx"), "XX");
const l = M.layoutList({ layout: "br,us,de", variant: ",intl," }, { "br|": "Portuguese (Brazil)", "us|": "English (US)", "us|intl": "English (US, intl.)", "de|": "German" }, {});
eq(l[0].description, "Portuguese (BR)"); eq(l[0].variantLabel, "ABNT2");
eq(l[1].description, "English (US)"); eq(l[1].variantLabel, "Intl");
eq(l[2].description, "German (DE)"); eq(l[2].variantLabel, "Standard");
console.log("ok   - keyboard language names with a 2-3 letter country, and a variant for every layout");'
