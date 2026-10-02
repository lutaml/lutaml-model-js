#!/usr/bin/env ruby
# frozen_string_literal: true

# Build script for @lutaml/lutaml-model. Runs Opal::Builder against
# lutaml-model's lib/ to produce both flavors.
#
# Mirrors the load-path setup that lutaml-model's Rakefile applies for
# `bundle exec rake spec:opal`. Three categories of paths go onto
# Opal's compile-time load path so that the lutaml/model entry point
# pulls in the full XML adapter surface (Oga via the vendored fork,
# REXML via the bundled stdlib gem + moxml's compat shadows).
#
# Key fix: OPAL_PREFORK_DISABLE=1 selects Opal 1.8.x's built-in
# Sequential scheduler, avoiding the Prefork deadlock on this
# gem's 516 autoloads. Opal 2 also adds a Threaded scheduler.

require "opal"
require "opal/builder"
require "fileutils"
require "rubygems"

ENV["OPAL_PREFORK_DISABLE"] ||= "1"

# Gems whose Ruby source cannot be Opal-compiled. Each becomes a no-op
# stub so `require "..."` resolves without pulling in C extensions or
# unsupported stdlib. Anything NOT in this list ships in the bundle.
#
# What we no longer stub (vs the previous build):
#   - lutaml/xml  : full XML module compiles cleanly now
#   - oga         : vendored opal-oga fork provides pure-Ruby lexer
#   - rexml/*     : REXML gem source is on the load path; moxml ships
#                   lib/compat/opal/rexml/* shadows for the bits Opal
#                   can't follow natively
#
# What we still stub:
#   - nokogiri / ox : C extensions, no Opal equivalent
#   - monitor / thread / set : Ruby stdlib that Opal's stdlib doesn't
#                              ship; runtime_compatibility.rb already
#                              stubs Mutex/ConditionVariable/Thread
#                              at the call sites that need them
#   - weakref       : runtime_compatibility.rb provides the runtime
#                     WeakRef class; Opal still follows the file-level
#                     `require "weakref"` at compile time even though
#                     the `unless Lutaml::Model.opal?` guard skips it
#                     at runtime
#   - oga/xml/sax_parser, oga/html/sax_parser, oga/xml/pull_parser:
#                     the opal-oga fork's lib/oga.rb requires these
#                     unconditionally, but they call `Kernel#eval` at
#                     FILE-LOAD time to define handler methods
#                     dynamically. Opal's eval needs `opal-parser`
#                     (an extra ~500 KB and slow at runtime). Stub them
#                     out — lutaml-model uses Oga's basic
#                     XML::Parser/document API, not SAX or pull-parser.
#                     oga/xpath/context is NOT stubbed: its eval is
#                     inside a method body, only fired on call.
#   - jruby / liboga / libll : referenced inside platform conditionals
#                              (RUBY_PLATFORM == 'java' etc.) that Opal
#                              still follows at compile time even though
#                              they won't execute at runtime
#   - rdf/linkeddata stack : large, only needed for jsonld/yamlld/turtle
#                            formats which are optional in lutaml-model
#   - fuzzy_match   : external gem not in the Opal bundle
#   - leptris, leptris/xml/descriptor, liquid,
#     openssl       : required by lutaml-model code paths outside the
#                     XML/model surface this bundle ships (templating,
#                     descriptors, digests); Opal still follows the
#                     requires at compile time
UPSTREAM_STUBS = %w[
  nokogiri
  ox
  monitor
  thread
  set
  weakref
  oga/xml/sax_parser
  oga/html/sax_parser
  oga/xml/pull_parser
  jruby
  liboga
  libll
  rdf
  rdf/turtle
  rdf-turtle
  rdf/ntriples
  rdf/model
  linkeddata
  json/ld
  jsonld
  json-ld
  rdf/vocab
  spira
  fuzzy_match
  leptris
  liquid
  leptris/xml/descriptor
  openssl
].freeze

PATCH_DIR = File.expand_path("patches", __dir__)

# moxml fixes not yet in a moxml release (see README). The installed gem
# is never edited: each patched file is copied into an overlay directory
# in the build checkout, patched there, and the overlay goes first on
# Opal's load path so it shadows the gem's copy.
def moxml_overlay_dir(ruby_dir)
  moxml_gem_dir = Gem::Specification.find_by_name("moxml").gem_dir
  overlay = File.join(ruby_dir, ".opal-overlay")
  Dir[File.join(PATCH_DIR, "moxml", "*.patch")].sort.each do |patch|
    rel = File.read(patch)[%r{^\+\+\+ b/lib/(\S+)}, 1] or abort "no target in #{patch}"
    dest = File.join(overlay, rel)
    FileUtils.mkdir_p(File.dirname(dest))
    FileUtils.cp(File.join(moxml_gem_dir, "lib", rel), dest)
    ok = system("patch", "--forward", "--no-backup-if-mismatch", dest, "-i", patch)
    abort "moxml patch failed: #{patch} against moxml #{Gem.loaded_specs["moxml"]&.version}" unless ok
  end
  overlay
end

ENTRY = "js_bundle_entry"

# Add every load-path element the Opal compiler needs to follow
# `require` chains out of lib/lutaml/model.rb and lib/lutaml/xml.rb.
# Each path is idempotent — Opal::Builder#append_paths dedupes.
def append_compile_load_paths!(builder, ruby_dir)
  # Patched copies of gem files (see moxml_overlay_dir) win over the gems.
  builder.append_paths(moxml_overlay_dir(ruby_dir))

  # lutaml-model itself
  builder.append_paths(File.join(ruby_dir, "lib"))

  # lutaml-model's lib/compat/opal/ ships lutaml_model_boot.rb and
  # the moxml/yaml/rexml compat shims that boot the Opal runtime.
  # js_bundle_entry (the ENTRY above) also lives here.
  builder.append_paths(File.join(ruby_dir, "lib", "compat", "opal"))

  # Opal's own stdlib + corelib. Several runtime requires target files
  # under these paths (e.g. moxml's compat/opal/rexml_compat.rb does
  # `require "corelib/array/pack"`; nodejs/yaml pulls in nodejs/).
  # Opal::Builder does not put them on its compile load path by default.
  opal_gem_dir = Gem::Specification.find_by_name("opal")&.gem_dir
  if opal_gem_dir
    builder.append_paths(File.join(opal_gem_dir, "opal"))
    builder.append_paths(File.join(opal_gem_dir, "stdlib"))
  end

  # moxml — required by lutaml/xml.rb. moxml's lib/compat/opal/ ships
  # the rexml/* shadow files that override parts of REXML's source so
  # it parses cleanly under Opal.
  moxml_gem_dir = Gem::Specification.find_by_name("moxml")&.gem_dir
  if moxml_gem_dir
    builder.append_paths(File.join(moxml_gem_dir, "lib"))
    builder.append_paths(File.join(moxml_gem_dir, "lib", "compat", "opal"))
  end

  # REXML is a bundled Ruby stdlib gem. Its source must be on the
  # load path so `require "rexml/document"` and the transitive
  # `require "rexml/formatters/pretty"` (from moxml's customized_rexml)
  # resolve. Opal cannot follow Ruby's default LOAD_PATH on its own.
  rexml_lib = $LOAD_PATH.find do |p|
    File.exist?(File.join(p, "rexml", "document.rb"))
  end
  builder.append_paths(rexml_lib) if rexml_lib

  # The opal-oga and opal-ruby-ll forks (vendored as submodules in
  # lutaml-model) provide pure-Ruby lexer/driver implementations under
  # ext/pureruby/ that switch in via RUBY_PLATFORM == 'opal' in their
  # lib/oga.rb / lib/ll/setup.rb entry points. Both lib/ and
  # ext/pureruby/ must be on the load path so the conditional resolves.
  %w[opal-oga opal-ruby-ll].each do |fork_name|
    fork_path = File.join(ruby_dir, "vendor", fork_name)
    next unless File.directory?(fork_path)

    builder.append_paths(File.join(fork_path, "lib"))
    builder.append_paths(File.join(fork_path, "ext", "pureruby"))
  end
end

def build_app_code(ruby_dir, dist_dir)
  builder = Opal::Builder.new
  append_compile_load_paths!(builder, ruby_dir)
  builder.stubs = UPSTREAM_STUBS.dup
  builder.prerequired = %w[opal]
  builder.compiler_options = { source_map: false }

  output = builder.build(ENTRY).to_s
  output
end

# Compile scripts/smoke_test.rb as a separate Opal module so test.js
# can run a real XML round-trip via Opal.require("smoke_test") after
# the structural check passes.
#
# Opal.compile wraps top-level output in `Opal.queue(function(Opal){...})`
# which defers execution — useless for Opal.require which calls the
# module function synchronously and expects the body to run inline.
# Strip the queue wrapper so the body executes directly inside the
# `Opal.modules["smoke_test"] = function(Opal) { ... }` registration.
def compile_smoke_test(_ruby_dir, scripts_dir)
  smoke_src = File.join(scripts_dir, "smoke_test.rb")
  return "" unless File.exist?(smoke_src)

  compiled = Opal.compile(File.read(smoke_src), file: "smoke_test.rb")
  body = compiled
         .sub(/\AOpal\.queue\(function\(Opal\)\s*\{/, "")
         .sub(/\}\);\s*\z/, "")
  %(\nOpal.modules["smoke_test"] = function(Opal) {\n#{body}\n};\n)
end

def read_runtime(runtime_pkg_root)
  candidates = [
    File.join(runtime_pkg_root, "node_modules", "@lutaml", "opal-runtime", "dist", "runtime.js"),
    File.join(runtime_pkg_root, "node_modules", "@lutaml", "opal-runtime", "dist", "runtime.cjs"),
  ]
  candidates.each do |p|
    next unless File.exist?(p)

    runtime = File.read(p)
    warn "read runtime from #{p} (#{runtime.bytesize / 1024} KiB)"
    return runtime
  end
  abort "Could not locate @lutaml/opal-runtime/dist/runtime.js under " \
        "#{runtime_pkg_root}/node_modules; run npm install first"
end

def build_self_contained(app_code, runtime, ruby_ref, dist_dir)
  header = <<~HEADER
    // @lutaml/lutaml-model — self-contained build (Opal runtime embedded)
    // Generated from lutaml-model #{ruby_ref}
    // Opal runtime: @lutaml/opal-runtime
    //
  HEADER
  combined = "#{header}#{runtime}\n#{app_code}"
  path = File.join(dist_dir, "lutaml-model.js")
  File.write(path, combined)
  warn "wrote #{path} (#{combined.bytesize / 1024} KiB)"
end

def write_types(dist_dir)
  dts = <<~TS
    declare const Lutaml: any;
    export = Lutaml;
    export default Lutaml;
  TS
  path = File.join(dist_dir, "index.d.ts")
  File.write(path, dts)
  warn "wrote #{path}"
end

ruby_dir = ENV.fetch("RUBY_DIR")
dist_dir = ENV.fetch("DIST_DIR")
runtime_root = ENV.fetch("RUNTIME_PKG_ROOT")
scripts_dir = File.expand_path("scripts", runtime_root)
ruby_ref = ENV.fetch("RUBY_REF")

FileUtils.mkdir_p(dist_dir)

app_code = build_app_code(ruby_dir, dist_dir)
smoke_code = compile_smoke_test(ruby_dir, scripts_dir)
combined = smoke_code.empty? ? app_code : "#{app_code}\n#{smoke_code}"

# External flavor (no embedded runtime): just the combined app code.
no_opal_path = File.join(dist_dir, "lutaml-model-no-opal.js")
FileUtils.mkdir_p(dist_dir)
File.write(no_opal_path, combined)
warn "wrote #{no_opal_path} (#{combined.bytesize / 1024} KiB)"

runtime = read_runtime(runtime_root)
build_self_contained(combined, runtime, ruby_ref, dist_dir)
write_types(dist_dir)
