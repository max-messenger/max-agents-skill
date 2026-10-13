
## Priority when sources disagree

1. **dev.max.ru** (DOCS, BRIDGE) — behaviour, limits, requirements, dates.
2. **api-schema** — request/response shapes, field names, enums (where the site is silent).
3. **Client source code** (Go, TS) — how the official clients actually call the API; may lag the schema.
4. READMEs, tutorials, demo bots.

Note: dev.max.ru pages hide some code examples in inactive tabs (e.g. TypeScript/Python/Go/Java
variants). When reading a page programmatically, the visible HTML may not include them.

## The sources

| ID | Link | Use it for | Fast path |
|----|------|-----------|-----------|
| DOCS | https://dev.max.ru/docs-api | Every Bot API method, object, limit, error; API changelog | Methods: `/docs-api/methods/<VERB>/<path>` (path params as `-chatId-`), objects: `/docs-api/objects/<Name>`, changes: `/docs-api/changelog-api` |
| BRIDGE | https://dev.max.ru/docs/webapps/bridge | `window.WebApp` API for mini-apps | Validation: `/docs/webapps/validation`; setup: `/docs/webapps/introduction`; deeplinks: `/help/deeplinks` |
| SCHEMA | https://github.com/max-messenger/api-schema | OpenAPI `schema.yaml` — exact fields, enums, required flags | `schema.yaml` → `paths:` and `components/schemas`; `README.mdx` for base URL and generator notes |
| GO | https://github.com/max-messenger/max-bot-api-client-go (branch `v2`) | Official Go client (primary Go path) | `bot.go` (NewApi, GetHandler, ValidateInitData), `option.go`, `messages.go`, `upload.go`, `subscriptions.go`, `model/`, `docs/01–04`, `example/simple` |
| MAXBOT | https://github.com/max-messenger/maxbot | Optional Go framework on top of the client (routing, context, middleware) | `api.go`, `context.go`, `option.go`, `example/simple` |
| DEMO | https://github.com/max-messenger/demo-bot-go | Production-style Go bot: scenarios, keyboards, uploads, chat admin, tests | `internal/app/services/bot/scenario/*.go` (pins older versions — don't copy them) |
| TS | https://github.com/max-messenger/max-bot-api-client-ts | Official TypeScript client/framework `@maxhub/max-bot-api` | `docs/01–10`, `examples/*.ts`, `src/core/context.ts`, `src/core/network/api/` |
| UI | https://github.com/max-messenger/max-ui | React component library `@maxhub/max-ui` for mini-apps | `src/components/index.ts`, `README.md`, `docs/MIGRATION.md`, `CHANGELOG.md`; site `https://dev.max.ru/ui` lags the repo |
| CERT | https://www.gosuslugi.ru/crt | Russian Trusted Root CA (Минцифры) — required to call `platform-api2.max.ru` | PEM: `https://gu-st.ru/content/lending/russian_trusted_root_ca_pem.crt` — see `tls-trust.md` |

## When to re-check a source instead of trusting this skill

- Any date-bound statement (host migration, removed/restricted methods, webhook TLS rules).
- Exact client method signatures before writing a lot of code against them.
- Anything marked "Note:" as a DOCS-vs-SCHEMA difference.
- Errors that contradict the skill (e.g. an endpoint returning 404 or a field being rejected).
