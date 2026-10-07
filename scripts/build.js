// Build script for @lutaml/lutaml-model.
//
// Clones lutaml-model at RUBY_REF (default: LUTAML_MODEL_REF below),
// checks out its submodules (the opal-oga and opal-ruby-ll forks),
// regenerates the ragel/ruby-ll outputs the forks gitignore, then runs
// the Opal build via scripts/build.rb.
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const ROOT = process.cwd();
const DIST = path.join(ROOT, "dist");
const TMP = path.join(ROOT, ".tmp");

// RUBY_REF defaults to the pinned LUTAML_MODEL_REF. For dev builds, set
// RUBY_REF to a branch/SHA explicitly (e.g. "main" or a commit hash).
const LUTAML_MODEL_REF = "v0.8.96";
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
buildRuby();
rmrf(TMP);
console.error("build complete");
