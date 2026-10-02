// Build script for @lutaml/lutaml-model.
//
// Clones lutaml-model at RUBY_REF (default: LUTAML_MODEL_REF below),
// checks out its submodules (the opal-oga and opal-ruby-ll forks),
// regenerates the ragel/ruby-ll outputs the forks gitignore, applies the
// Opal patches in scripts/patches/lutaml-model/, then runs the Opal build
// via scripts/build.rb.
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const ROOT = process.cwd();
const DIST = path.join(ROOT, "dist");
const TMP = path.join(ROOT, ".tmp");

// The lutaml-model release this package is built from. This package's
// own version is not the gem's, so it cannot name the ref (`v0.1.0` is
// an unrelated old gem tag). The patches in scripts/patches/ are made
// against this ref: move them together. For dev builds, set RUBY_REF to
// a branch/tag/SHA explicitly.
const LUTAML_MODEL_REF = "v0.8.88";
const RUBY_REF = process.env.RUBY_REF || LUTAML_MODEL_REF;
const RUBY_REPO =
  process.env.RUBY_REPO || "https://github.com/lutaml/lutaml-model.git";

function run(cmd, opts = {}) {
  console.error(`$ ${cmd}`);
  try {
    return execSync(cmd, { stdio: ["ignore", "inherit", "inherit"], ...opts });
  } catch (err) {
    console.error(`command failed: ${cmd}`);
    process.exit(1);
  }
}

// Same, but returns whether the command succeeded instead of exiting.
function succeeds(cmd, opts = {}) {
  try {
    execSync(cmd, { stdio: "ignore", ...opts });
    return true;
  } catch (err) {
    return false;
  }
}

function rmrf(p) { fs.rmSync(p, { recursive: true, force: true }); }
function ensureDir(p) { fs.mkdirSync(p, { recursive: true }); }

function checkoutLutamlModel() {
  rmrf(TMP);
  ensureDir(TMP);
  // --recurse-submodules: lutaml-model vendors opal-oga and
  // opal-ruby-ll as submodules; both must be present for the Opal
  // compiler to find the pure-Ruby lexer/driver fallbacks.
  //
  // git clone --branch only accepts branch/tag names, not SHAs. For
  // SHA refs (e.g. js-sync-main dev builds that pin to a commit),
  // do a shallow fetch of the exact SHA instead.
  const isSha = /^[0-9a-f]{40}$/i.test(RUBY_REF);
  if (isSha) {
    run(`git init ${TMP}`);
    run(`git -C ${TMP} remote add origin ${RUBY_REPO}`);
    run(`git -C ${TMP} fetch --depth 1 origin ${RUBY_REF}`);
    run(`git -C ${TMP} checkout FETCH_HEAD`);
    run(
      `git -C ${TMP} submodule update --init --recursive --depth 1`,
    );
  } else {
    run(
      `git clone --depth 1 --recurse-submodules --shallow-submodules ` +
        `--branch ${RUBY_REF} ${RUBY_REPO} ${TMP}`,
    );
  }

  // The forks ship grammar sources (.rl/.rll) but gitignore the
  // generated .rb/.c outputs. Ragel + ruby-ll must regenerate them
  // before bundle install compiles the C extensions via each fork's
  // extconf.rb (which requires ext/c/lexer.c to exist).
  run("gem install ruby-ll --no-document");
  run("rake vendor:prepare", { cwd: TMP });

  run("bundle install", { cwd: TMP });
}

// Opal fixes not yet in a lutaml-model release (see README). A patch
// whose change the checkout already has (a ref that includes the
// upstream fix) is skipped; one that neither applies nor is already
// there stops the build rather than shipping without it.
function applyGemPatches() {
  const dir = path.join(ROOT, "scripts", "patches", "lutaml-model");
  for (const f of fs.readdirSync(dir).filter((n) => n.endsWith(".patch")).sort()) {
    const patch = path.join(dir, f);
    const opts = { cwd: TMP };
    if (!succeeds(`patch -p1 --forward --dry-run -i ${patch}`, opts) &&
        succeeds(`patch -p1 --reverse --dry-run -i ${patch}`, opts)) {
      console.error(`already applied, skipping: ${f}`);
      continue;
    }
    run(`patch -p1 --forward --no-backup-if-mismatch -i ${patch}`, opts);
  }
}

function buildRuby() {
  const env = {
    ...process.env,
    RUBY_DIR: TMP,
    DIST_DIR: DIST,
    RUNTIME_PKG_ROOT: ROOT,
    RUBY_REF,
    OPAL_PREFORK_DISABLE: "1",
  };
  run(`bundle exec ruby ${path.join(ROOT, "scripts", "build.rb")}`, {
    cwd: TMP,
    env,
  });
}

rmrf(DIST);
ensureDir(DIST);
checkoutLutamlModel();
applyGemPatches();
buildRuby();
rmrf(TMP);
console.error("build complete");
