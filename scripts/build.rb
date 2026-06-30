#!/usr/bin/env ruby
# frozen_string_literal: true

# Build script for @lutaml/lutaml-model. Runs Opal::Builder against
# lutaml-model's lib/ to produce both flavors.
#
# Key fix: OPAL_PREFORK_DISABLE=1 selects Opal 1.8.x's built-in
# Sequential scheduler, avoiding the Prefork deadlock on this
# gem's 516 autoloads. Opal 2 also adds a Threaded scheduler.

require "opal"
require "opal/builder"
require "fileutils"

ENV["OPAL_PREFORK_DISABLE"] ||= "1"

# Deps that cannot be Opal-compiled directly. Each becomes a no-op
# stub; runtime equivalents come from peer packages or host shims.
UPSTREAM_STUBS = %w[
  lutaml/xml
  nokogiri
  ox
  oga
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
  weakref
  rexml/document
  rexml/streamlistener
  rexml/parsers/baseparser
  rexml/parsers/treeparser
  rexml/light/node
  rexml/text
  logger
  fuzzy_match
].freeze

ENTRY = "lutaml/model"

def build_app_code(ruby_dir, dist_dir)
  builder = Opal::Builder.new
  builder.append_paths(File.join(ruby_dir, "lib"))
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