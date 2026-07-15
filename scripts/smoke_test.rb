# frozen_string: true

# Round-trip smoke test compiled into the @lutaml/lutaml-model bundle.
# Invoked from scripts/test.js via `Opal.require("smoke_test")` after
# the structural check passes.
#
# Verifies that the JS bundle can actually do XML work end-to-end:
# parses XML, builds model instances, and serializes back. Exercises
# both Oga (default) and REXML (opt-in) adapters so a regression in
# either is caught before publish.

module LutamlJS
  module SmokeTest
    class << self
      def build_model
        Class.new do
          include Lutaml::Model::Serialize

          attribute :name, :string
          attribute :age, :integer

          xml do
            element "person"
            map_attribute "age", to: :age
            map_element "name", to: :name
          end
        end
      end

      def verify_oga
        klass = build_model
        Lutaml::Model::Config.xml_adapter_type = :oga

        instance = klass.from_xml('<person age="42"><name>Alice</name></person>')
        return false unless instance.name == "Alice"
        return false unless instance.age == 42

        xml = instance.to_xml
        return false unless xml.include?("<name>Alice</name>")

        true
      end

      def verify_rexml
        klass = build_model
        Lutaml::Model::Config.xml_adapter_type = :rexml

        instance = klass.from_xml('<person age="17"><name>Bob</name></person>')
        return false unless instance.name == "Bob"
        return false unless instance.age == 17

        xml = instance.to_xml
        return false unless xml.include?("<name>Bob</name>")

        true
      end

      def verify
        oga_ok = verify_oga
        rexml_ok = verify_rexml
        # Module-level ivars so JS callers can introspect per-adapter
        # outcomes without parsing Opal's Hash wrapper.
        @oga_ok = oga_ok
        @rexml_ok = rexml_ok
        oga_ok && rexml_ok
      rescue StandardError => e
        warn "smoke_test error: #{e.class}: #{e.message}"
        @error = "#{e.class}: #{e.message}"
        false
      end

      attr_reader :oga_ok, :rexml_ok, :error
    end
  end
end
