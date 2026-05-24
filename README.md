# kiket-ext-github

GitHub evidence adapter for [Kiket](https://kiket.dev) — registers the extension manifest and re-exports the TypeScript normalizer from the monorepo.

## Layout

| Path | Purpose |
| ---- | ------- |
| `extension.yaml` | Platform extension manifest (repo root — not `.kiket/`) |
| `src/index.ts` | Re-exports `@kiket/github-adapter` for packaging and tests |

Normalization logic lives in the Kiket monorepo at `packages/github-adapter`. This submodule is the installable extension repo (`kiket-ext-github`).

## Install on a workspace

Register the extension with the platform API:

```http
POST /platform/extensions
```

Configure credentials and an event source, then route GitHub webhooks to `/integrations/github/webhook`. See the integration guide for full setup.

## Documentation

- [GitHub webhook ingestion](https://docs.kiket.dev/docs/integrations/github-webhook-ingestion)

## Development (monorepo)

When checked out inside the Kiket workspace, install from the repo root:

```bash
pnpm install
pnpm --filter @kiket/ext-github check
pnpm --filter @kiket/ext-github test
```

Standalone CI in this repo validates `extension.yaml` and entrypoint presence only; build and tests run in the monorepo where `@kiket/github-adapter` is linked via `workspace:*`.
