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

## Sync model

This package is rebuilt automatically whenever the Ruby source changes:

| Ruby event | Trigger | JS dist-tag |
|---|---|---|
| Tag push (stable release) | \`repository_dispatch(do-release)\` from lutaml-model's release chain | \`latest\` |
| Push to \`main\` | \`repository_dispatch(js-sync-main)\` from lutaml-model's \`.github/workflows/js-sync.yml\` | \`next\` |
| Pull request touching \`lib/\` | \`repository_dispatch(js-pr-check)\` from lutaml-model's \`.github/workflows/js-pr-check.yml\` | (no publish; smoke test only) |

Install the latest dev build with:

\`\`\`sh
npm install @lutaml/lutaml-model@next
\`\`\`

## Source

Built from [lutaml-model](https://github.com/lutaml/lutaml-model) by its
release workflow. The Ruby gem remains the single source of truth.
