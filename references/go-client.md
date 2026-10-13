# Go client: `max-bot-api-client-go`

**Contents:** [Install](#install) · [Constructor + options](#constructor--options) · [Service groups (exact signatures)](#service-groups-exact-signatures) · [Message builder (maxbot.NewMessage())](#message-builder-maxbotnewmessage) · [Keyboard builder (model.NewKeyboard())](#keyboard-builder-modelnewkeyboard) · [Uploads](#uploads) · [Long polling](#long-polling) · [Webhook](#webhook) · [Callback answers](#callback-answers) · [Comments API](#comments-api) · [ValidateInitData (mini-app initData)](#validateinitdata-mini-app-initdata) · [Errors, retries — and no rate limiting](#errors-retries--and-no-rate-limiting) · [Pitfalls (not already covered above)](#pitfalls-not-already-covered-above)

> Source: GO github.com/max-messenger/max-bot-api-client-go/v2 v2.4.0 (sha c832c5b, 2026-09-08) · verified 2026-09-21. If this looks outdated, check the repo.

This is the **primary** Go path for MAX bots: a thin, low-level wrapper over the Bot API.
For a batteries-included router/context/middleware layer on top of it, see
[`go-maxbot.md`](./go-maxbot.md) — optional, not required.

## Install

```bash
go mod init your-bot
go get github.com/max-messenger/max-bot-api-client-go/v2
```

Root package name is `maxbot` (import path ends in `/v2`, but the Go package itself is
`maxbot`). Model types live in the `model` sub-package. Both the raw client and the
separate `maxbot` framework repo (`go-maxbot.md`) are named `maxbot` — if a file imports
both, alias one explicitly, e.g. `rawclient "github.com/max-messenger/max-bot-api-client-go/v2"`.

```go
import (
	maxbot "github.com/max-messenger/max-bot-api-client-go/v2"
	"github.com/max-messenger/max-bot-api-client-go/v2/model"
)
```

## Constructor + options

<!-- nocompile -->
```go
func NewApi(token string, opt ...Opt) (*Api, error)
```

`Api` exposes six service groups, all populated inside `NewApi`:

<!-- nocompile -->
```go
type Api struct {
	Bots          BotsAPI
	Upload        UploadAPI
	Chats         ChatsAPI
	Messages      MessagesAPI
	Comments      CommentsAPI
	Subscriptions SubscriptionsAPI
}
```

Default host is `platform-api2.max.ru` (`DefaultHostV2`); the old `platform-api.max.ru`
constant exists only as `// Deprecated: not allowed` and is never used unless you pass it
to `WithBaseURL` yourself. Auth is a raw `Authorization: <token>` header — **no** `Bearer`
prefix.

Functional options (`Opt func(cli *client) error`):

| Option | Effect |
|---|---|
| `WithHTTPClient(cli HttpClient)` | swap the transport — this is where you plug in a custom CA trust store; see [`tls-trust.md`](./tls-trust.md) for the Минцифры root CA setup, required for outbound calls to `platform-api2.max.ru` |
| `WithBaseURL(baseURL string)` | override scheme+host |
| `WithPollingPause(d time.Duration)` | pause between long-poll retries (default 1s) |
| `WithPollingTimeout(d time.Duration)` | long-poll `timeout` query param (default 30s) |

```go
import (
	"net/http"
	"os"
	"time"

	maxbot "github.com/max-messenger/max-bot-api-client-go/v2"
)

func newClient() (*maxbot.Api, error) {
	httpClient := &http.Client{Timeout: 25 * time.Second}
	return maxbot.NewApi(
		os.Getenv("MAX_BOT_TOKEN"),
		maxbot.WithHTTPClient(httpClient),
		maxbot.WithPollingTimeout(30*time.Second),
	)
}
```

Never set `InsecureSkipVerify` on the `http.Client`'s `Transport` — see `tls-trust.md`
for the correct way to trust the Минцифры root CA.

## Service groups (exact signatures)

All methods take `ctx context.Context` as the first argument (omitted below for width).
Types are in the `model` sub-package unless noted; `*maxbot.Message`/`*maxbot.Comment` are
the builder types below.

| Group | Method | Returns |
|---|---|---|
| `Bots` | `GetMyInfo()` | `BotInfo` |
| | `EditMyInfo(patch BotPatch)` — deprecated, use `PatchCommands` for commands | `BotInfo` |
| | `PatchCommands(botPatch BotPatchCommands)` | `BotPatchCommands` |
| `Chats` | `GetChat(chatID int64)` | `Chat` |
| | `EditChat(chatID int64, patch ChatPatch)` | `Chat` |
| | `DeleteChat(chatID int64)` | `SimpleQueryResult` |
| | `SendAction(chatID int64, action SenderAction)` | `SimpleQueryResult` |
| | `GetPinnedMessage(chatID int64)` | `GetPinnedMessageResult` |
| | `PinMessage(chatID int64, messageID string, notify bool)` | `SimpleQueryResult` |
| | `UnpinMessage(chatID int64)` | `SimpleQueryResult` |
| | `GetMembership(chatID int64)` | `ChatMember` |
| | `LeaveChat(chatID int64)` | `SimpleQueryResult` |
| | `GetAdmins(chatID int64)` | `ChatMembersList` |
| | `SetAdmins(chatID int64, admins []ChatAdmin)` | `SimpleQueryResult` |
| | `DeleteAdmins(chatID, userID int64)` | `SimpleQueryResult` |
| | `GetMembers(chatID, marker, count int64, userIDs []int64)` — marker-based pagination | `ChatMembersList` |
| | `AddMembers(chatID int64, userIDs []int64)` | `SimpleQueryResult` |
| | `RemoveMember(chatID, userID int64, block bool)` | `SimpleQueryResult` |
| `Messages` | `GetMessages(chatID, from, to, count int64, messageIDs []string)` | `MessageList` |
| | `GetMessageByID(messageID string)` | `Message` |
| | `Send(msg *maxbot.Message)` | `SendMessageResult` |
| | `EditMessage(messageID string, body NewMessageBody)` | `SimpleQueryResult` |
| | `DeleteMessage(messageID string)` | `SimpleQueryResult` |
| | `AnswerOnCallback(callbackID string, answer CallbackAnswer)` | `SimpleQueryResult` |
| | `GetVideoAttachmentDetails(videoToken string)` | `VideoAttachmentDetails` |
| `Subscriptions` | `GetSubscriptions()` | `GetSubscriptionsResult` |
| | `Subscribe(url, secret string, updateTypes []string, version string)` | `SimpleQueryResult` |
| | `Unsubscribe(url string)` | `SimpleQueryResult` |
| | `GetUpdates(marker int64)` | `([]Update, int64, error)` |
| `Comments` | `GetComments(postID string, before, after, count int64, commentIds []string)` | `CommentList` |
| | `GetCommentByID(postID, commentID string)` | `Comment` |
| | `Send(postID string, comment *maxbot.Comment)` | `SendMessageResult` |
| | `Edit(postID, commentID string, comment *maxbot.Comment)` | `SendMessageResult` |
| | `Delete(postID, commentID string)` | `SendMessageResult` |
| `Upload` | `Upload(uploadType UploadType, reader io.Reader, name string, size int64)` | `(string, error)` |

There is **no** `GET /chats` list method — `Chats` only has `GetChat(chatID)` (single
chat by numeric id). The endpoint was removed from the API in June 2026; track chats
yourself via `bot_added`/`bot_removed`/`bot_started` events instead (see `patterns.md`).

## Message builder (`maxbot.NewMessage()`)

Fluent, all setters return `*Message`: `SetUser`/`SetChat`/`SetText`/`SetFormat` (
`model.FormatMarkdown`/`model.FormatHTML`)/`SetDisableLinkPreview`/`AddImageUrl`/
`AddSticker`/`AddContact`/`AddLocation(lat, lot float64)`/`AddShare`/`WithoutNotify`/
`SetReply(text, id)`/`AddKeyboard`/`AddAttachByToken(token, model.AttachmentType)`/
`AddAttachments([]model.Attachment)`.

- **Pitfall:** `AddAttachments` **replaces** the whole attachments slice; every other
  `Add*` method appends. Calling `AddSticker(...)` then `AddAttachments(...)` silently
  drops the sticker.
- **Pitfall:** there is no `Reply(text, msg)` shorthand despite what
  `docs/02-listen-and-respond.md` shows — use `SetReply(text, id string)`.
- A sent message's id is at `result.Message.Body.Mid`, not a top-level `MessageID` field.

```go
import (
	"context"
	"fmt"

	maxbot "github.com/max-messenger/max-bot-api-client-go/v2"
	"github.com/max-messenger/max-bot-api-client-go/v2/model"
)

func sendGreeting(ctx context.Context, api *maxbot.Api, chatID int64) error {
	msg := maxbot.NewMessage().
		SetChat(chatID).
		SetText("**Hello** from the bot").
		SetFormat(model.FormatMarkdown)

	result, err := api.Messages.Send(ctx, msg)
	if err != nil {
		return fmt.Errorf("send message: %w", err)
	}
	_ = result.Message.Body.Mid // save for later edit/reply/delete
	return nil
}
```

## Keyboard builder (`model.NewKeyboard()`)

<!-- nocompile -->
```go
func NewKeyboard() *Keyboard
func (k *Keyboard) AddRow() *KeyboardRow
func (k *Keyboard) Build() Attachment
```

Row methods (chainable, called on the row): `AddCallBack(text, payload)`,
`AddLink(text, url)`, `AddGeoLocation(text string, quick bool)`, `AddContact(text)`,
`AddMessage(text)`, `AddOpenApp(text string, botID int64)`, `AddClipboard(text, payload)`.

- **Pitfall:** `AddOpenApp` stuffs the button *label* into the `WebApp` field (comment in
  source: `// ignored, required`) and the bot id into `ContactID` — it is not a generic
  "open any URL" button. The mini-app URL itself is configured server-side against the
  bot (masterBot settings), not passed here.
- **Pitfall:** `AddCallback(text, intent, payload)` (lowercase `b`) is
  `// Deprecated: use AddCallBack` — the `Intent` argument is ignored.
- Numeric limits (≤210 buttons, ≤30 rows, ≤7/row, ≤3/row for link/open_app/
  request_geo_location/request_contact) are **not** enforced in this client — see
  `bot-api.md` for the DOCS-sourced limits; violating them fails server-side.

```go
import (
	"context"
	"fmt"

	maxbot "github.com/max-messenger/max-bot-api-client-go/v2"
	"github.com/max-messenger/max-bot-api-client-go/v2/model"
)

func sendMenu(ctx context.Context, api *maxbot.Api, chatID int64) error {
	kb := model.NewKeyboard()
	kb.AddRow().
		AddLink("Open MAX", "https://max.ru").
		AddCallBack("Audio", "audio").
		AddCallBack("Video", "video")

	msg := maxbot.NewMessage().SetChat(chatID).SetText("Choose:").AddKeyboard(kb)
	if _, err := api.Messages.Send(ctx, msg); err != nil {
		return fmt.Errorf("send menu: %w", err)
	}
	return nil
}
```

## Uploads

`Upload.Upload(ctx, uploadType, reader, name, size) (token string, err error)`. Flow:

1. Client calls `POST /uploads?type=<image|video|audio|file>` and gets back a
   **one-shot, server-issued** `{token?, url}` — there is no fixed per-type host
   hardcoded in the client (don't hardcode `iu.oneme.ru`/`fu.oneme.ru`/etc. yourself
   either; the server decides).
2. Client streams the file as `multipart/form-data` to that `url`.
3. Token comes from step 1's response for `UploadAudio`/`UploadVideo`, from the POST
   response body for `UploadImage`/`UploadFile`.

- **Pitfall:** `Upload.Upload` itself has **no retry** — a single attempt. The
  `attachment.not.ready` retry (see Errors below) happens on the *subsequent*
  `Messages.Send`/`Comments.*` call that references the token, not on the upload call.
- **Pitfall:** for `UploadImage`, if the server ever returns more than one photo-size
  entry, the client picks whichever Go map key it iterates first — non-deterministic.

```go
import (
	"context"
	"fmt"
	"os"

	maxbot "github.com/max-messenger/max-bot-api-client-go/v2"
	"github.com/max-messenger/max-bot-api-client-go/v2/model"
)

func sendDocument(ctx context.Context, api *maxbot.Api, userID int64, path string) error {
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open file: %w", err)
	}
	defer f.Close()

	info, err := f.Stat()
	if err != nil {
		return fmt.Errorf("stat file: %w", err)
	}

	token, err := api.Upload.Upload(ctx, model.UploadFile, f, info.Name(), info.Size())
	if err != nil {
		return fmt.Errorf("upload file: %w", err)
	}

	msg := maxbot.NewMessage().SetUser(userID).AddAttachByToken(token, model.AttachFile)
	if _, err := api.Messages.Send(ctx, msg); err != nil { // retries attachment.not.ready internally
		return fmt.Errorf("send document: %w", err)
	}
	return nil
}
```

## Long polling

`Subscriptions.GetUpdates(ctx, marker int64) ([]model.Update, int64, error)` —
`GET /updates?limit=50&timeout=<pollTimeout>&marker=<marker>`. `limit` is fixed at 50, not
configurable. Persist the returned marker and pass it back in on the next call.

- **Pitfall:** the pattern shown in the upstream `docs/01-your-first-bot.md` —
  `select { case <-ctx.Done(): default: ... }` with an **empty** `ctx.Done()` case — does
  not exit the loop; it busy-spins until `GetUpdates` itself errors out. Add an explicit
  `return`, as below.

```go
import (
	"context"
	"log"

	maxbot "github.com/max-messenger/max-bot-api-client-go/v2"
	"github.com/max-messenger/max-bot-api-client-go/v2/model"
)

func pollUpdates(ctx context.Context, api *maxbot.Api, handle func(context.Context, model.Update)) {
	var marker int64
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		updates, next, err := api.Subscriptions.GetUpdates(ctx, marker)
		if err != nil {
			log.Println("GetUpdates:", err)
			return
		}
		marker = next
		for _, update := range updates {
			handle(ctx, update)
		}
	}
}
```

## Webhook

Subscribe: `Subscriptions.Subscribe(ctx, url, secret, updateTypes, version)` →
`POST /subscriptions`. Receive: `Api.GetHandler(handler UpdateHandler, secret string) http.HandlerFunc`
where `type UpdateHandler func(context.Context, model.Update)`. Mount it on any path with
`net/http`. TLS/port/retry-schedule requirements (443 only, HTTPS, 8h auto-unsubscribe,
must return 200 within 30s) are server-side — see `bot-api.md`. For the Минцифры root CA
needed for your **outbound** calls (not the inbound webhook), see `tls-trust.md`.

```go
import (
	"context"

	maxbot "github.com/max-messenger/max-bot-api-client-go/v2"
)

func subscribeWebhook(ctx context.Context, api *maxbot.Api, url, secret string) error {
	types := []string{"message_created", "message_callback", "bot_started"}
	_, err := api.Subscriptions.Subscribe(ctx, url, secret, types, "1")
	return err
}
```

**Security note:** `GetHandler`'s own secret check is a plain `secret != r.Header.Get(...)`
comparison — **not** constant-time (unlike `ValidateInitData` below, which does use
`subtle.ConstantTimeCompare`). If you treat the webhook secret as a security boundary,
wrap it with your own constant-time check in front:

```go
import (
	"crypto/subtle"
	"net/http"

	maxbot "github.com/max-messenger/max-bot-api-client-go/v2"
)

func secureWebhook(api *maxbot.Api, handler maxbot.UpdateHandler, secret string) http.HandlerFunc {
	inner := api.GetHandler(handler, secret)
	return func(w http.ResponseWriter, r *http.Request) {
		got := r.Header.Get("X-Max-Bot-Api-Secret")
		if subtle.ConstantTimeCompare([]byte(got), []byte(secret)) != 1 {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		inner(w, r) // GetHandler's own (non-constant-time) check now trivially passes
	}
}
```

`GetHandler` calls your handler synchronously and writes no response body on success —
Go's `net/http` sends an empty `200 OK`. Keep the handler fast; dispatch slow work to a
goroutine yourself (see `patterns.md` for the fast-ack pattern with idempotency).

## Callback answers

`Messages.AnswerOnCallback(ctx, callbackID string, answer model.CallbackAnswer) (model.SimpleQueryResult, error)`
→ `POST /answers?callback_id=<id>`. `CallbackAnswer{Message *model.NewMessageBody,
Notification *string}` — both optional; set `Message` to edit the message, `Notification`
for a toast, or both. DOCS caps this at ≤2/sec per chat — not enforced client-side, so
throttle yourself (see `patterns.md`).

```go
import (
	"context"
	"fmt"

	maxbot "github.com/max-messenger/max-bot-api-client-go/v2"
	"github.com/max-messenger/max-bot-api-client-go/v2/model"
)

func toast(ctx context.Context, api *maxbot.Api, callbackID, text string) error {
	answer := model.CallbackAnswer{Notification: &text}
	if _, err := api.Messages.AnswerOnCallback(ctx, callbackID, answer); err != nil {
		return fmt.Errorf("answer callback: %w", err)
	}
	return nil
}
```

## Comments API

Scoped under `/messages/{postID}/comments[/{commentID}]` — `postID` is a message id.
Builder: `maxbot.NewComment(text string) *Comment` (defaults to `model.FormatMarkdown`),
`SetFormat`, `SetLink(CommentLink{Type, Mid})`. `Send`/`Edit`/`Delete` retry on
`attachment.not.ready` like `Messages.Send`; `GetComments`/`GetCommentByID` do not.
Comments never allow `attachments` on the request body.

```go
import (
	"context"
	"fmt"

	maxbot "github.com/max-messenger/max-bot-api-client-go/v2"
	"github.com/max-messenger/max-bot-api-client-go/v2/model"
)

func replyAsComment(ctx context.Context, api *maxbot.Api, postID string) error {
	comment := maxbot.NewComment("Thanks for the post!").SetFormat(model.FormatMarkdown)
	if _, err := api.Comments.Send(ctx, postID, comment); err != nil {
		return fmt.Errorf("send comment: %w", err)
	}
	return nil
}
```

## `ValidateInitData` (mini-app initData)

```go
func ValidateInitData(initData string, botToken string) (res model.InitData, err error)
```

Built into the client. It internally derives
`secretKey = HMAC_SHA256(key="WebAppData", msg=botToken)`, then compares
`HMAC_SHA256(key=secretKey, msg=dataCheckString)` with `subtle.ConstantTimeCompare`
(constant-time, unlike the webhook secret check above) — that part of the check is sound.
Full algorithm and the mini-app phone-hash formula are documented once, in
`webhooks-and-security.md`; this is just the Go entry point.

- **Pitfall (verified, v2.4.0):** `ValidateInitData` **double URL-decodes** — it calls
  `url.QueryUnescape` on the whole raw `initData` string first, then `url.ParseQuery` on
  the result, which percent-decodes each key/value *again*. Any value that legitimately
  contains an encoded `&`, `=`, or `%` (e.g. a user's first name is `Tom&Jerry`, encoded as
  `Tom%2526Jerry` at the outer layer) gets mangled before the check-string is rebuilt, so
  the recomputed hash no longer matches and **valid initData is rejected**. Do not treat
  this function as the safe default for untrusted real-world user data (names, bios, etc.
  can contain these characters); use the standalone, single-decode validator in
  `webhooks-and-security.md` instead, or re-verify this bug is fixed before relying on it.

```go
import (
	"fmt"

	maxbot "github.com/max-messenger/max-bot-api-client-go/v2"
)

func verifyInitData(initData, botToken string) error {
	data, err := maxbot.ValidateInitData(initData, botToken)
	if err != nil {
		return fmt.Errorf("invalid init data: %w", err)
	}
	_ = data.User // model.UserApp{ID, FirstName, LastName, LanguageCode, PhotoURL}
	return nil
}
```

## Errors, retries — and no rate limiting

```go
type Error struct {
	Code    string `json:"code"`
	Err     string `json:"error,omitempty"`
	Message string `json:"message"`
}
func (e Error) IsAttachmentNotReady() bool // e.Code == "attachment.not.ready"

type TimeoutError struct{ Op, Reason string }
type NetworkError struct{ Op string; Err error }
```

Built-in retries are narrow, not general resilience:

- `Messages.Send` and `Comments.{Send,Edit,Delete}` retry **only** on
  `Code == "attachment.not.ready"` (up to 3 attempts, 1s/2s backoff). Any other API error
  aborts immediately.
- `Subscriptions.GetUpdates` retries on any error except `context.Canceled`/
  `context.DeadlineExceeded` (same schedule).
- **No other method retries.** `Upload.Upload`, `Bots.*`, `Chats.*`, plain
  `Messages.{Get*,Edit,Delete}`, `Subscriptions.{Subscribe,Unsubscribe,GetSubscriptions}`
  each call the API once.
- **The client does not rate-limit itself anywhere.** DOCS' 30 rps cap and the
  2/sec-per-chat callback-answer cap are entirely your responsibility — see the rate
  limiter recipe in `patterns.md`.

```go
import (
	"errors"

	maxbot "github.com/max-messenger/max-bot-api-client-go/v2"
)

func isRetryable(err error) bool {
	var apiErr *maxbot.Error
	if errors.As(err, &apiErr) {
		return apiErr.IsAttachmentNotReady()
	}
	var timeout *maxbot.TimeoutError
	return errors.As(err, &timeout)
}
```

## Pitfalls (not already covered above)

1. `EditMyInfo` is `// Deprecated: use PatchCommands`, but `PatchCommands` only patches
   `/me/commands` — use `EditMyInfo`/`model.BotPatch` for other profile fields (e.g.
   description) until a non-deprecated alternative exists.
2. The public tutorial `dev.max.ru/docs/chatbots/bots-coding/go` describes a pre-v2 API
   (`maxbot.New`, `GetBot`, a channel-based `GetUpdates`) that does not exist in this
   v2.4.0 source — do not follow it; use the signatures on this page instead.

Other pitfalls are called out inline where they're relevant: `AddAttachments` overwriting
(Message builder), `AddOpenApp`'s field reuse and numeric limits (Keyboard builder),
non-deterministic image-token selection and zero upload retry (Uploads), the non-constant-
time webhook secret check (Webhook), and the narrow `attachment.not.ready`-only retry
scope with no built-in rate limiting (Errors).
