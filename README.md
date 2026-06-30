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

## Build note: OPAL_PREFORK_DISABLE=1

Opal 1.8.x defaults to its \`Prefork\` scheduler, which deadlocks on
this gem's 516 autoloads. The build sets \`OPAL_PREFORK_DISABLE=1\`
to select Opal's built-in \`Sequential\` scheduler (same one used
under Windows or when running inside Opal itself).

Opal 2 master adds a \`Threaded\` scheduler as well. Once Opal 2
ships, the env var becomes unnecessary.

## Runtime status

Compile succeeds (~1.5 MB bundle). Runtime has a known issue:
\`lib/lutaml/model.rb:275\` and \`lib/lutaml/xml.rb:205\` both call
\`Lutaml::Model::Serializable.prepend(...)\` for Opal's MRO workaround.
Ruby forbids double-prepend → \`RuntimeError\`.

Fix is documented in lutaml-model's \`TODO.opal/\` plan — needs
upstream PR to deduplicate the prepend calls.

## Source

Built from [lutaml-model](https://github.com/lutaml/lutaml-model) by its
release workflow. The Ruby gem remains the single source of truth.
