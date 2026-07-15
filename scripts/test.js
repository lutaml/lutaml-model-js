// Smoke test for @lutaml/lutaml-model — verify the build artifacts load.
const path = require("path");
const fs = require("fs");

const variant = process.env.VARIANT || "self-contained";
const distDir = path.join(__dirname, "..", "dist");

let runtimePath;
let appPath;
if (variant === "external") {
  try {
    runtimePath = require.resolve("@lutaml/opal-runtime");
  } catch (e) {
    console.error("external variant requires @lutaml/opal-runtime");
    process.exit(1);
  }
  appPath = path.join(distDir, "lutaml-model-no-opal.js");
} else {
  runtimePath = path.join(distDir, "lutaml-model.js");
  appPath = null;
}

if (!fs.existsSync(runtimePath)) {
  console.error(`missing artifact: ${runtimePath}`);
  process.exit(1);
}
if (appPath && !fs.existsSync(appPath)) {
  console.error(`missing artifact: ${appPath}`);
  process.exit(1);
}

require(runtimePath);
if (appPath) require(appPath);

const Opal = globalThis.Opal;
if (typeof Opal !== "object" || typeof Opal.require !== "function") {
  console.error("Opal global not initialized");
  process.exit(1);
}
console.log(`✓ runtime exposed Opal global`);

const moduleNames = Object.keys(Opal.modules || {});
const lutamlModules = moduleNames.filter((n) => n.startsWith("lutaml/"));
if (lutamlModules.length === 0) {
  console.error("no lutaml/* modules registered with Opal");
  process.exit(1);
}
console.log(
  `✓ ${lutamlModules.length} lutaml/* modules registered ` +
    `(sample: ${lutamlModules.slice(0, 3).join(", ")})`
);

// Actually load lutaml/model + lutaml/xml + run a real XML round-trip
// through both Oga (default) and REXML adapters. The smoke_test
// module is compiled into the bundle by build.rb and registers
// LutamlJS::SmokeTest.verify → boolean.
if (!moduleNames.includes("smoke_test")) {
  console.error("smoke_test module not registered (build.rb didn't compile it)");
  process.exit(1);
}

Opal.require("lutaml/model");
Opal.require("lutaml/xml");
Opal.require("smoke_test");

// Top-level Ruby constants live on Opal.Object, not Opal.top.
const LutamlJS = Opal.Object.$const_get("LutamlJS");
const SmokeTest = LutamlJS.$const_get("SmokeTest");
const ok = SmokeTest.$verify();
if (ok !== true) {
  const err = SmokeTest.$error();
  console.error(`✗ XML round-trip failed${err ? `: ${err}` : ""}`);
  process.exit(1);
}
console.log(`✓ XML round-trip via Oga adapter verified`);
console.log(`✓ XML round-trip via REXML adapter verified`);

console.log(`\n${variant} variant: structure + round-trip verified`);
process.exit(0);