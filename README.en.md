# MAX Messenger Agent Skill

[Русский](README.md) · **English**

[![Agent Skills](https://img.shields.io/badge/Agent_Skills-SKILL.md-2f6feb)](https://agentskills.io)
[![Verified](https://img.shields.io/badge/verified_against_docs-2026--09--21-2da44e)](references/sources.md)
[![License](https://img.shields.io/badge/license-Apache--2.0-lightgrey)](LICENSE)

The MAX platform changes fast, and AI agents need current context to write working code.

MAX Messenger Agent Skill is a set of skills that lets AI agents build bots and mini-apps
for the [MAX](https://max.ru) messenger:

- Bot API
- Webhooks
- Libraries for configuring bot scenarios in Go and TypeScript
- MAX Bridge library for working with mini-apps
- MAX UI kit `@maxhub/max-ui`

MAX Messenger Agent Skill works in Claude Code, Codex, Cursor, Gemini CLI, OpenCode, GitHub Copilot, Cline,
Claude Desktop and any agent that reads the [Agent Skills](https://agentskills.io) format.

## Installing MAX Messenger Agent Skill

Install the skill for every agent on your machine from the max-agents-skill repository:

- In a macOS or Linux terminal, WSL or Git Bash:

  ```bash
  curl -fsSLO https://raw.githubusercontent.com/max-messenger/max-agents-skill/main/install.sh && bash install.sh
  ```

- With the [skills CLI](https://github.com/vercel-labs/skills) package manager:

  ```bash
  npx skills add max-messenger/max-agents-skill -g
  ```

### How the skill is installed for each agent

| Agent | How it is installed |
|-------|---------------------|
| Codex, Cursor, Gemini CLI, OpenCode, GitHub Copilot | `install.sh` copies the skill files into the shared folder `~/.agents/skills`, which these agents read on their own |
| Claude Code | `install.sh` creates a symlink in the agent's folder `~/.claude/skills`. When the agent reads that folder, the link takes it straight to the skill |
| Cline | `install.sh` creates a symlink in the agent's folder `~/.cline/skills`. When the agent reads that folder, the link takes it straight to the skill |
| Claude Desktop, Cowork, claude.ai | `install.sh` packs the skill into `max-messenger-skill.zip` and puts it in your Downloads folder. Upload the archive manually in [Skills settings](https://support.claude.com/en/articles/12512180-using-skills-in-claude) |
| Any other agent | Copy the skill folder into the agent's skills directory and give the agent the command: install the "MAX Messenger" skill from `~/.agents/skills/max-messenger/INSTALL.md` — read the instructions and follow them without asking |

If the agent doesn't find the skill after installation, give it this command:

```
Install the "MAX Messenger" skill from ~/.agents/skills/max-messenger/INSTALL.md — read the instructions and follow them without asking.
```

## Management and settings

### Update

To update the skill, run the script again:

```bash
bash install.sh
```

A backup of the previous version is created automatically in `~/.cache/agent-skills-backup/`.

### Uninstall

To remove the skill, run:

```bash
bash install.sh --uninstall
```

### Additional options

- To install a specific version:

  ```bash
  bash install.sh --ref v1.0.1
  # By default the version from the main branch is installed
  ```

- To install from a local copy:

  ```bash
  bash install.sh --local <dir>
  # Use it when the skill is already on your disk.
  # From a clone of the GitHub repository the script installs the local copy on its own, without this option
  ```

- To work only with the shared folder `~/.agents/skills` and skip creating symlinks:

  ```bash
  bash install.sh --no-links
  ```

- To skip building the `.zip` archive for Claude apps:

  ```bash
  bash install.sh --no-zip
  ```

- If GitHub is unreachable or blocked on your network:

  ```bash
  MAX_SKILL_TARBALL_URL=<mirror .tar.gz URL> bash install.sh
  # Replace <mirror .tar.gz URL> with the address of an alternative site
  # or a local server that hosts the archive
  ```

Only the `SKILL.md` and `INSTALL.md` files and the `references/` folder are installed into the skills directory.

## Example prompts

The skill activates when the agent gets a MAX-related request:

- "Write a Go bot for MAX that answers /start with an inline keyboard"
- "Set up a webhook for a MAX bot in TypeScript and verify the secret"
- "MAX mini-app in React with max-ui: request the phone number and validate initData on the backend"
- "My bot fails with x509: certificate signed by unknown authority in Docker — fix it"
- "Split a long text into MAX messages under the 4000-character limit"

## Scope of the skill

- **Bot API** — every method incl. comments, callback answers, pins, members and admins;
  media uploads, limits, errors, dated platform changes
- **TLS** — the Russian Trusted Root CA (Минцифры) for Go, Node, Docker, curl, Python
- **Security** — webhook secret, `initData`, phone and contact hashes; Go and TypeScript code
- **Libraries** — `max-bot-api-client-go` v2, `maxbot`, `@maxhub/max-bot-api`, MAX Bridge (`window.WebApp`), `@maxhub/max-ui`
- **Development patterns** — rate limiting, retries on errors, chat tracking, scheduled sending,
  text splitting, idempotency

## Architecture

### max-agents-skill repository structure

```
max-agents-skill/
├── SKILL.md                     core: constraints, stack choice, minimal bots, common mistakes
├── INSTALL.md                   installation instructions for the agent
├── install.sh                   installer
└── references/
    ├── bot-api.md               methods, uploads, limits, errors
    ├── objects-and-updates.md   messages, attachments, buttons, update types
    ├── formatting.md            supported markdown and html
    ├── tls-trust.md             Russian Trusted Root CA
    ├── webhooks-and-security.md webhooks, initData, hashes
    ├── go-client.md             official Go client
    ├── go-maxbot.md             maxbot framework
    ├── ts-client.md             @maxhub/max-bot-api
    ├── mini-apps-bridge.md      MAX Bridge
    ├── max-ui.md                @maxhub/max-ui
    ├── patterns.md              patterns
    └── sources.md               sources and versions
```

## Versions and sources

Verified against the official documentation and library sources on **2026-09-21**.

The code compiles (`go vet`, `tsc --strict`) against these versions:

| Package | Version |
|---------|---------|
| `github.com/max-messenger/max-bot-api-client-go/v2` | v2.4.0 |
| `github.com/max-messenger/maxbot` | v1.1.0 (Go ≥ 1.26) |
| `@maxhub/max-bot-api` | 0.3.1 (Node ≥ 20.19, ESM) |
| `@maxhub/max-ui` | 0.5.0 (React 19.2.8) |

If the skill disagrees with a source or looks outdated, rely on the information:

- [dev.max.ru/docs-api](https://dev.max.ru/docs-api)
- [MAX Bridge](https://dev.max.ru/docs/webapps/bridge)
- [api-schema](https://github.com/max-messenger/api-schema)
- [Go client](https://github.com/max-messenger/max-bot-api-client-go)
- [maxbot](https://github.com/max-messenger/maxbot)
- [TS client](https://github.com/max-messenger/max-bot-api-client-ts)
- [max-ui](https://github.com/max-messenger/max-ui)

Source priority order is in [`references/sources.md`](references/sources.md).

## License

[Apache-2.0](LICENSE)
