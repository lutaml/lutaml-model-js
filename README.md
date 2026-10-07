# @lutaml/lutaml-model

JavaScript release of [lutaml-model](https://github.com/lutaml/lutaml-model),
Opal-compiled and published as `@lutaml/lutaml-model` on npm.

## Install

\`\`\`sh
npm install @lutaml/lutaml-model
\`\`\`

## Flavors

| Entry | File | Use case |
|---|---|---|
| \`lutaml-model\` (default) | \`dist/lutaml-model.js\` | **Self-contained** — Opal runtime embedded. CDN-friendly. |
| \`lutaml-model-no-opal\` | \`dist/lutaml-model-no-opal.js\` | **External** — references \`@lutaml/opal-runtime\` global. For bundler users who share runtime. |

## XML adapters

Both pure-Ruby XML adapters from the Ruby gem ship in the bundle:

- **Oga** — default. Compiled from the vendored \`opal-oga\` fork, which
  provides a pure-Ruby lexer under \`ext/pureruby/\` selected via
  \`RUBY_PLATFORM == 'opal'\` in \`lib/oga.rb\`.
- **REXML** — opt-in via \`Lutaml::Model::Config.xml_adapter_type = :rexml\`.
  Compiled from the bundled stdlib gem, with moxml's
  \`lib/compat/opal/rexml/*\` shadows patching the parts Opal can't
  follow natively.

Nokogiri and Ox are stubbed (C extensions, no Opal equivalent).

## Build note: OPAL_PREFORK_DISABLE=1

Opal 1.8.x defaults to its \`Prefork\` scheduler, which deadlocks on
this gem's 516 autoloads. The build sets \`OPAL_PREFORK_DISABLE=1\`
to select Opal's built-in \`Sequential\` scheduler (same one used
under Windows or when running inside Opal itself).

Opal 2 master adds a \`Threaded\` scheduler as well. Once Opal 2
ships, the env var becomes unnecessary.

## Build: pinned source

`scripts/build.js` builds from the lutaml-model release pinned in
`LUTAML_MODEL_REF`; set `RUBY_REF` to build another tag, branch or SHA.
This package's version is not the gem's, so it never names the ref.

The pin is v0.8.96, the first release with the Opal fixes from
lutaml/lutaml-model#914. Its moxml dependency resolves to the latest
release, which includes the fixes from lutaml/moxml#320 (moxml 0.5.105 and later);
\`scripts/build.rb\` fails if the bundle resolves an older moxml.

## Sync model

This package is rebuilt automatically whenever the Ruby source changes:

| Ruby event | Trigger | JS dist-tag |
|---|---|---|
| Stable release | \`repository_dispatch(do-release)\` with \`client_payload.ruby_ref\` set to the tag to build (required; no sender yet) | \`latest\` |
| Manual release | \`workflow_dispatch\` from the pin in \`LUTAML_MODEL_REF\`, or from its \`ruby_ref\` input | \`latest\` |
| Push to \`main\` | \`repository_dispatch(js-sync-main)\` from lutaml-model's \`.github/workflows/js-sync.yml\` | \`next\` |
| Pull request touching \`lib/\` | \`repository_dispatch(js-pr-check)\` from lutaml-model's \`.github/workflows/js-pr-check.yml\` | (no publish; smoke test only) |

Install the latest dev build with:

\`\`\`sh
npm install @lutaml/lutaml-model@next
\`\`\`

## Source

Built from [lutaml-model](https://github.com/lutaml/lutaml-model) by its
release workflow. The Ruby gem remains the single source of truth.
