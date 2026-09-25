#!/usr/bin/env bash
# Node unit test of the keyboard widget's layout names (needs node; the widget itself does not).
set -euo pipefail
cd "$(dirname "$0")/../plugins/orbital.keyboard"
node -e '
const M = require("./KeyboardModel.js"), eq = (a, b) => { if (a !== b) { console.log("FAIL -", a, "!=", b); process.exit(1) } };
eq(M.standardName("br", ""), "BR · ABNT2");
eq(M.standardName("br", "abnt2"), "BR · ABNT2");
eq(M.standardName("br", "nodeadkeys"), "BR · No dead keys");
eq(M.standardName("us", ""), "US");
eq(M.standardName("us", "intl"), "US · Intl");
eq(M.standardName("epo", ""), "EPO");
eq(M.standardName("trans", ""), "TRA");
const l = M.layoutList({ layout: "br,us", variant: ",intl" }, { "br|": "Portuguese (Brazil)" }, {});
eq(l[0].description, "BR · ABNT2"); eq(l[1].description, "US · Intl"); eq(l[0].fullDescription, "Portuguese (Brazil)");
console.log("ok   - keyboard layout names: 2-3 letter country plus variant detail");'
