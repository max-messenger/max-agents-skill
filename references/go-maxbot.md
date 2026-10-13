# Go framework: `maxbot` (optional layer)

> Source: MAXBOT github.com/max-messenger/maxbot v1.1.0 (sha 83efd1c, 2026-09-11) · depends on `max-bot-api-client-go/v2` v2.4.0 · verified 2026-09-21. If this looks outdated, check the repo.

`maxbot` is a router/context/middleware layer built **on top of** the raw client
documented in [`go-client.md`](./go-client.md) (the primary Go path). Reach for it when
you want handler registration, a `Context` facade, and a polling/webhook run-loop out of
the box; reach for the raw client directly when you need full control over dispatch,
retries, or persistence — `maxbot` adds none of those itself.

**Requires Go 1.26+.** `maxbot` v1.1.0 declares `go 1.24.0` in its `go.mod`, but `api.go` calls
`errors.AsType`, which was added to the standard library in Go 1.26. On Go 1.24/1.25 the import
fails with `undefined: errors.AsType`. Set `go 1.26` (or `toolchain go1.26.x`) in your `go.mod`.
Verified 2026-09-21: builds on go1.26.0, fails on go1.25.6. The raw client (`go-client.md`) works
on Go 1.24+.

Both the raw client and this framework use the Go package name `maxbot`. Import only the
framework in a file (plus the raw client's `model` sub-package, which has a different
package name) to avoid aliasing:

```go
import (
	"github.com/max-messenger/max-bot-api-client-go/v2/model"
	"github.com/max-messenger/maxbot"
)
```

## Install

```bash
go get github.com/max-messenger/maxbot
```

## What it adds over the raw client

- A flat `map[string]HandlerFunc` router: exact command strings (`/help`), event-type
  constants (`message_created`), and callback payloads (looked up with an internal
  `"callback_"` prefix) all share one map.
- Dispatch order per update: callback match first, then command match, then raw
  update-type match — first hit wins.
- A `Context` facade over message building (`Send`/`Answer`/`Reply`/`Edit`/`Delete`).
- Onion-style middleware (`Use`, per-route middleware, `middleware.Recover`).
- Run-mode glue: `Start`/`Stop`, a polling loop, webhook subscribe + handler — so
  application code never touches `Subscriptions.GetUpdates`/`Subscribe` directly.
- Handlers run in **goroutines** (`go f()` inside dispatch) — both webhook and polling
  paths are fire-and-forget; the webhook HTTP response is not blocked on your handler.

It does **not** add rate limiting, retries beyond what the raw client already does, or
persistence — `demo-bot-go` builds its own Redis-backed state/lock layer on top (see
below).

## Exact API

<!-- nocompile -->
```go
func NewApi(token string, opt ...Opt) (*Api, error)
func (a *Api) Use(middleware ...MiddlewareFunc)
func (a *Api) Handle(endpoint string, h HandlerFunc, m ...MiddlewareFunc)
func (a *Api) HandleCallback(endpoint string, h HandlerFunc, m ...MiddlewareFunc)
func (a *Api) Start()
func (a *Api) Stop()
func (a *Api) WebhookHandler() http.HandlerFunc
func (a *Api) Client() *maxbot.Api // the raw client, for calls maxbot doesn't wrap
func (a *Api) OnError(err error, c Context)
```

`Start()` is a no-op if a webhook URL was configured via `WithWebhook`; otherwise it
starts long polling. `Stop()` cancels the internal context, breaking the polling loop.
Command matching checks the update's `BotName` against the bot's own username (from
`GetMyInfo`, fetched once at construction) — if empty, the bot always answers, assuming
it's the only bot in the chat.

## Minimal bot

Adapted from `example/simple/main.go`. `bot.Start()` here uses the default (polling)
mode; uncomment `WithWebhook` and swap in `bot.WebhookHandler()` for webhook mode. Requires Go 1.26+.

```go
package main

import (
	"log"
	"net/http"
	"os"
	"time"

	"github.com/max-messenger/max-bot-api-client-go/v2/model"
	"github.com/max-messenger/maxbot"
)

func main() {
	opts := []maxbot.Opt{
		maxbot.WithHTTPClient(&http.Client{Timeout: 25 * time.Second}),
	}

	bot, err := maxbot.NewApi(os.Getenv("MAX_BOT_TOKEN"), opts...)
	if err != nil {
		log.Fatal(err)
	}

	bot.Handle("/help", func(c maxbot.Context) error {
		kb := model.NewKeyboard()
		kb.AddRow().
			AddLink("Docs", "https://dev.max.ru/docs").
			AddCallBack("Press me", "pushBtn")
		return c.Send("Menu:", maxbot.WithKeyboard(kb))
	})

	bot.HandleCallback("pushBtn", func(c maxbot.Context) error {
		return c.Answer("Got it", maxbot.WithMessageID(c.Update().MessageID))
	})

	bot.Handle(maxbot.OnChatTitleChangedEvent, func(c maxbot.Context) error {
		return c.Send("Chat title changed")
	})

	bot.Start()
}
```

- `/start` and other commands are **not** special-cased by `maxbot` — they are plain
  string keys you register yourself via `Handle`.
- To subscribe to a real webhook you must list the desired event constants explicitly in
  `WithWebhook` (e.g. `maxbot.OnBotAdded`, `maxbot.OnMessageCreated`,
  `maxbot.OnMessageCallback`).

## Handlers, `Context`, middleware

<!-- nocompile -->
```go
type HandlerFunc func(Context) error
type MiddlewareFunc func(HandlerFunc) HandlerFunc

type Context interface {
	Update() model.Update
	Context() context.Context
	WithValue(ctx context.Context, key, value any)
	API() *maxbot.Api // raw client escape hatch

	Send(text string, opts ...Option) error
	Answer(text string, opts ...Option) error
	Reply(text string, opts ...Option) error
	Edit(text string, opts ...Option) error
	Delete(opts ...Option) error
}
```

- `Send` addresses a new message to the update's user/chat.
- `Answer` answers the **callback** on the current update
  (`Messages.AnswerOnCallback(..., c.u.GetCallback().CallbackID, ...)`). On a plain message
  update there is no callback: `GetCallback()` returns a zero value, so the call does not panic
  but sends an empty `callback_id` and fails at the API. Use `Answer` only in callback handlers.
- `Reply` quotes the message that triggered the update (`SetReply`).
- `Edit`/`Answer` **wipe existing buttons/attachments by default** — pass
  `maxbot.WithAttachments(...)` to carry them over.
- `Delete` deletes the message from the current update.

Middleware is standard Go onion-style: `Api.Use(...)` appends to a global chain applied to
handlers registered **afterward** (call `Use` before `Handle`, it is not retroactive);
`Handle`/`HandleCallback` also take per-route middleware appended after the global chain.

`middleware.Recover(onError ...RecoverFunc) maxbot.MiddlewareFunc` wraps a handler in
`defer/recover`. Pitfall: it silently drops any panic value that is neither an `error`
nor a `string` (no `default:` branch), so `panic(42)` or `panic(struct{}{})` is swallowed
without a log line.

```go
import (
	"log"

	"github.com/max-messenger/maxbot"
	"github.com/max-messenger/maxbot/middleware"
)

func withRecovery(bot *maxbot.Api) {
	bot.Use(middleware.Recover(func(err error, c maxbot.Context) {
		log.Println("recovered:", err)
	}))
}
```

## Options

`Opt` (bot construction, passed to `NewApi`):

| Name | Effect |
|---|---|
| `WithHTTPClient(cli maxbot.HttpClient)` | forwards to the raw client's own option |
| `WithBaseURL(baseURL string)` | forwards to the raw client |
| `WithPollingPause(d time.Duration)` | forwards to the raw client |
| `WithPollingTimeout(d time.Duration)` | forwards to the raw client |
| `WithErrorHandle(f func(error, Context))` | sets the framework's own `onError` (default: `log.Println`) |
| `WithWebhook(webhookUrl, secret string, types []string)` | switches `Start()` to webhook mode; **requires all 3 args** — the README's own quickstart calls it with 1 argument, which does not compile |

`Option` (per-message, passed to `Context.Send/Answer/Reply/Edit/Delete`):

`WithKeyboard(*model.Keyboard)`, `WithFormat(model.TextFormat)`, `WithChat(id int64)`,
`WithUser(id int64)`, `WithAttachByToken(fileToken string, at model.AttachmentType)`,
`WithAttachments([]model.Attachment)` (carry over attachments that `Edit`/`Answer` would
otherwise wipe), `WithMessageID(messageID string)`.

## Run modes

- **Polling** (default): `Start()` loops `Subscriptions.GetUpdates` with no explicit sleep
  of its own (pacing comes from `WithPollingPause`/`WithPollingTimeout` forwarded to the
  raw client). A `*maxbot.TimeoutError` is treated as an empty page and swallowed; **any
  other error stops the loop permanently** — no restart/backoff, and no `OnError` call
  either, so a network blip can silently end update delivery. Monitor the goroutine
  yourself in production.
- **Webhook**: set `WithWebhook(url, secret, types)`; `Start()` becomes a no-op (the
  subscribe call already ran during `NewApi`) and you mount `bot.WebhookHandler()`
  yourself with `net/http`. Secret verification is delegated entirely to the raw client's
  `GetHandler` (plain `!=`, not constant-time — see `go-client.md`'s Webhook section for
  the constant-time wrapping pattern, which applies here too since `WebhookHandler()` is a
  thin pass-through).

## When to use vs the raw client

Use **maxbot** when you want a quick single-process bot and are fine with its dispatch
order, goroutine-per-update model, and lack of built-in persistence/rate-limiting. Use the
**raw client** directly (`go-client.md`) when you need: a different router/framework
(chi, custom command trees), explicit control over concurrency and backoff, or you're
already building the surrounding service (state store, metrics, graceful shutdown)
yourself — at that point `maxbot`'s router adds little and its opinions (goroutine
dispatch, no backoff on polling errors) can get in the way.

## `demo-bot-go` architecture pointers

`demo-bot-go` is MAX's own reference bot, built on `maxbot`. Useful patterns to borrow
(don't copy its pinned versions — it pins `maxbot v0.0.2` + client `v2.1.0`, both stale;
use v1.1.0/v2.4.0 as verified here):

- **fx module tree** (`uber-go/fx`): a `pkg/connections/maxbot` module builds one
  `maxbot.Api` per configured bot from YAML, unconditionally adds
  `middleware.Recover(...)` plus OpenTelemetry/Prometheus middleware, then runs
  `go api.Start()`.
- **Router**: `go-chi/chi/v5`; the webhook path is registered by the maxbot connection
  pool itself (`r.Handle(cfg.Path, mw.WebhookHandler(pool.WebhookHandler(), log))`), not a
  hand-written controller. No additional webhook-secret check is added at this layer —
  it's still the raw client's job.
- **State/sessions**: Redis-backed `ScenarioState{Scenario, Step, Data}` per user, 30 min
  TTL by default, guarded by a distributed Redis lock per user id to serialize concurrent
  updates for the same user.
- **Scenario registry**: a plain `map[string]Scenario`; `Registry.Add` panics on a
  duplicate name — a startup-time crash, not a recoverable error.
- **Rate limiting gap**: demo ships a generic, reusable `pkg/ratelimiter` module but never
  wires it into the bot service — the reference bot itself performs zero outbound rate
  limiting against the MAX API. Don't assume "MAX's own bot rate-limits" from reading it.
- **Group-permission gating**: before a scenario that needs chat-admin rights, demo calls
  `Chats.GetMembership` to check the bot's own granted permissions against what the
  scenario declares, and warns rather than failing silently.

