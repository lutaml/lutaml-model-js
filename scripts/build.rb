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
#   - weakref     : runtime_compatibility.rb provides an Opal stub
#
# What we still stub:
#   - nokogiri / ox : C extensions, no Opal equivalent
#   - rdf/linkeddata stack : large, only needed for jsonld/yamlld/turtle
#                            formats which are optional in lutaml-model
#   - fuzzy_match   : external gem not in the Opal bundle
UPSTREAM_STUBS = %w[
  nokogiri
  ox
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
].freeze

ENTRY = "lutaml/model"

# Add every load-path element the Opal compiler needs to follow
# `require` chains out of lib/lutaml/model.rb and lib/lutaml/xml.rb.
# Each path is idempotent — Opal::Builder#append_paths dedupes.
def append_compile_load_paths!(builder, ruby_dir)
  # lutaml-model itself
  builder.append_paths(File.join(ruby_dir, "lib"))

  # lutaml-model's lib/compat/opal/ ships lutaml_model_boot.rb and
  # the moxml/yaml/rexml compat shims that boot the Opal runtime.
  builder.append_paths(File.join(ruby_dir, "lib", "compat", "opal"))

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
  path = File.join(dist_dir, "lutaml-model-no-opal.js")
  FileUtils.mkdir_p(dist_dir)
  File.write(path, output)
  warn "wrote #{path} (#{output.bytesize / 1024} KiB)"
  output
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
  warn "Could not locate @lutaml/opal-runtime/dist/runtime.js. " \
       "Self-contained flavor will be empty."
  ""
end

def build_self_contained(app_code, runtime, version, dist_dir)
  header = <<~HEADER
    // @lutaml/lutaml-model — self-contained build (Opal runtime embedded)
    // Generated from lutaml-model v#{version}
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
version = ENV.fetch("VERSION")

FileUtils.mkdir_p(dist_dir)

app_code = build_app_code(ruby_dir, dist_dir)
runtime = read_runtime(runtime_root)
build_self_contained(app_code, runtime, version, dist_dir)
write_types(dist_dir)
