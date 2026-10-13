# Patterns

**Contents:** [Rate limiting: global 30 rps + per-chat callback answers (≤2/s)](#rate-limiting-global-30-rps--per-chat-callback-answers-2s) · [attachment.not.ready retry](#attachmentnotready-retry) · [Tracking chats without GET /chats](#tracking-chats-without-get-chats) · [Scheduler for delayed sends (no send_at)](#scheduler-for-delayed-sends-no-send_at) · [Splitting text over 4000 characters](#splitting-text-over-4000-characters) · [Webhook: fast ack, async processing, idempotency](#webhook-fast-ack-async-processing-idempotency) · [Graceful shutdown](#graceful-shutdown)

> Source: GO github.com/max-messenger/max-bot-api-client-go/v2 v2.4.0 · TS @maxhub/max-bot-api 0.3.1 · limits from bot-api.md (DOCS, fetched 2026-09-21) · verified 2026-09-21. If this looks outdated, check the repos/site.

Neither client rate-limits, retries generally, or persists anything for you (see
`go-client.md`/`ts-client.md` "Errors" sections). These recipes fill the gaps DOCS calls
out. Each is intentionally minimal — swap the in-memory pieces for Redis/DB in production
where noted.

## Rate limiting: global 30 rps + per-chat callback answers (≤2/s)

DOCS: ~30 requests/sec to `platform-api2.max.ru` overall, and `POST /answers` (callback
replies) capped at ≤2/sec per chat — neither is enforced by either client. A small token
bucket covers both; key it globally for the first, per-chat-id for the second.

```go
package ratelimit

import (
	"context"
	"sync"
	"time"
)

// Limiter is a token bucket without background goroutines, so it is cheap to keep one per
// chat in a map (for the 2/s answer cap) next to one global instance (for 30 rps).
type Limiter struct {
	mu     sync.Mutex
	rate   float64 // tokens per second
	burst  float64
	tokens float64
	last   time.Time
}

// New returns a limiter allowing rps requests per second. rps must be > 0.
func New(rps int) *Limiter {
	if rps <= 0 {
		panic("ratelimit: rps must be > 0")
	}
	r := float64(rps)
	return &Limiter{rate: r, burst: r, tokens: r, last: time.Now()}
}

// Wait blocks until a token is available or ctx is done.
func (l *Limiter) Wait(ctx context.Context) error {
	for {
		l.mu.Lock()
		now := time.Now()
		l.tokens = min(l.burst, l.tokens+now.Sub(l.last).Seconds()*l.rate)
		l.last = now
		if l.tokens >= 1 {
			l.tokens--
			l.mu.Unlock()
			return nil
		}
		wait := time.Duration((1 - l.tokens) / l.rate * float64(time.Second))
		l.mu.Unlock()

		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(wait):
		}
	}
}
```

```typescript
// Same token bucket, reused for the global 30 rps cap and, keyed per chat id
// in a Map<number, RateLimiter>, for the 2/s answer cap.
export class RateLimiter {
  private tokens: number;
  private last = Date.now();

  // No timers: tokens refill lazily, so one instance per chat in a Map costs nothing when idle.
  constructor(private readonly rps: number) {
    if (!(rps > 0)) throw new RangeError('rps must be > 0');
    this.tokens = rps;
  }

  async wait(): Promise<void> {
    for (;;) {
      const now = Date.now();
      this.tokens = Math.min(this.rps, this.tokens + ((now - this.last) / 1000) * this.rps);
      this.last = now;
      if (this.tokens >= 1) {
        this.tokens -= 1;
        return;
      }
      await new Promise((r) => setTimeout(r, ((1 - this.tokens) / this.rps) * 1000));
    }
  }
}
```

## `attachment.not.ready` retry

Both SDKs already retry this automatically **inside `Messages.Send`/`Comments.*`** (Go: 3
attempts, 1s/2s backoff; TS: 3 attempts, 1s/2s/4s backoff) — don't wrap those calls in
your own retry loop, you'd be double-retrying. The gap is `Upload.Upload` itself, which
has zero retry in both clients: if the upload call fails transiently, retry the upload
manually before calling `Send`.

```go
import (
	"context"
	"errors"
	"io"
	"time"

	maxbot "github.com/max-messenger/max-bot-api-client-go/v2"
	"github.com/max-messenger/max-bot-api-client-go/v2/model"
)

func uploadWithRetry(ctx context.Context, api *maxbot.Api, r io.ReaderAt, name string, size int64) (string, error) {
	var lastErr error
	for attempt := 0; attempt < 3; attempt++ {
		token, err := api.Upload.Upload(ctx, model.UploadImage, io.NewSectionReader(r, 0, size), name, size)
		if err == nil {
			return token, nil
		}
		lastErr = err
		var netErr *maxbot.NetworkError
		if !errors.As(err, &netErr) {
			return "", err // not a transient network error, don't retry
		}
		time.Sleep(time.Duration(attempt+1) * time.Second)
	}
	return "", lastErr
}
```

```typescript
import type { Api } from '@maxhub/max-bot-api';

// ctx.api.uploadImage/uploadVideo/uploadAudio/uploadFile have no retry either.
// UploadImageOptions accepts { source: FileSource } or { url: string }.
export async function uploadWithRetry(
  api: Api,
  source: Parameters<Api['uploadImage']>[0],
  attempts = 3,
): Promise<Awaited<ReturnType<Api['uploadImage']>>> {
  let lastErr: unknown;
  for (let i = 0; i < attempts; i += 1) {
    try {
      return await api.uploadImage(source);
    } catch (err) {
      lastErr = err;
      await new Promise((r) => setTimeout(r, (i + 1) * 1000));
    }
  }
  throw lastErr;
}
```

## Tracking chats without `GET /chats`

The chat-listing endpoint was removed (June 2026; see `bot-api.md`). Persist chat ids
yourself from membership events as they arrive instead of trying to enumerate chats later.

```go
import (
	"context"

	"github.com/max-messenger/max-bot-api-client-go/v2/model"
)

// Store is your own persistence (DB table, KV store, etc.).
type Store interface {
	SaveChat(chatID int64)
	RemoveChat(chatID int64)
}

func trackChats(store Store) func(context.Context, model.Update) {
	return func(_ context.Context, u model.Update) {
		switch u.UpdateType {
		case "bot_added", "bot_started":
			store.SaveChat(u.ChatID)
		case "bot_removed":
			store.RemoveChat(u.ChatID)
		}
	}
}
```

```typescript
import type { Bot, Context } from '@maxhub/max-bot-api';

export interface ChatStore {
  save(chatId: number): Promise<void>;
  remove(chatId: number): Promise<void>;
}

export function trackChats(bot: Bot, store: ChatStore): void {
  bot.on('bot_added', async (ctx: Context) => { if (ctx.chatId) await store.save(ctx.chatId); });
  bot.on('bot_started', async (ctx: Context) => { if (ctx.chatId) await store.save(ctx.chatId); });
  bot.on('bot_removed', async (ctx: Context) => { if (ctx.chatId) await store.remove(ctx.chatId); });
}
```

## Scheduler for delayed sends (no `send_at`)

The API has no scheduled-send field (verified absent from `schema.yaml`) — delayed
sending is entirely client-side. An in-process timer is fine for short delays but is lost
on restart/deploy; for anything longer than a few minutes or that must survive a restart,
persist the job (DB row + poller, or a real queue) instead of holding it in memory.

```go
import (
	"context"
	"time"

	maxbot "github.com/max-messenger/max-bot-api-client-go/v2"
)

// ScheduleSend fires after d; cancel via the returned func. In-memory only —
// does not survive a process restart.
func ScheduleSend(ctx context.Context, api *maxbot.Api, chatID int64, text string, d time.Duration) func() {
	timer := time.AfterFunc(d, func() {
		msg := maxbot.NewMessage().SetChat(chatID).SetText(text)
		_, _ = api.Messages.Send(ctx, msg)
	})
	return func() { timer.Stop() }
}
```

```typescript
import type { Bot } from '@maxhub/max-bot-api';

// In-memory only — does not survive a process restart; persist for anything
// that must be durable.
export function scheduleSend(bot: Bot, chatId: number, text: string, delayMs: number): () => void {
  const handle = setTimeout(() => {
    bot.api.sendMessageToChat(chatId, text).catch(() => {});
  }, delayMs);
  return () => clearTimeout(handle);
}
```

## Splitting text over 4000 characters

`text` is capped at 4000 chars (`NewMessageBody`/`NewCommentBody`, confirmed in
`schema.yaml`). Split on paragraph breaks first, then on whitespace, so you don't cut a
word in half; this does **not** guarantee an open markdown/HTML span (e.g. an unclosed
`**bold**`) never spans a boundary — treat it as a best-effort heuristic, and prefer
splitting at your own paragraph boundaries when you control the source text.

The limit counts every character of the raw `text` (markup included) — characters, not bytes: Cyrillic takes 2 bytes per character in UTF-8, so
split on runes (Go) / code points (TS), never on byte or UTF-16 offsets.

```go
// splitMessage splits text into parts of at most limit characters (runes), preferring
// newline, then space boundaries in the second half of each chunk.
func splitMessage(text string, limit int) []string {
	r := []rune(text)
	var parts []string
	for len(r) > limit {
		cut := limit
		if i := lastRune(r[:limit], '\n'); i > limit/2 {
			cut = i
		} else if i := lastRune(r[:limit], ' '); i > limit/2 {
			cut = i
		}
		parts = append(parts, string(r[:cut]))
		r = r[cut:]
	}
	return append(parts, string(r))
}

func lastRune(r []rune, x rune) int {
	for i := len(r) - 1; i >= 0; i-- {
		if r[i] == x {
			return i
		}
	}
	return -1
}
```

```typescript
export function splitMessage(text: string, limit = 4000): string[] {
  // Array.from splits by code points, so emoji and other surrogate pairs are never cut in half.
  let rest = Array.from(text);
  const parts: string[] = [];
  while (rest.length > limit) {
    let cut = rest.lastIndexOf('\n', limit - 1);
    if (cut < limit / 2) cut = rest.lastIndexOf(' ', limit - 1);
    if (cut < limit / 2) cut = limit;
    parts.push(rest.slice(0, cut).join(''));
    rest = rest.slice(cut);
  }
  parts.push(rest.join(''));
  return parts;
}
```


## Webhook: fast ack, async processing, idempotency

Go's `Api.GetHandler` calls your handler **synchronously** before writing the response —
dispatch to a goroutine yourself if handling can be slow, and detach the context since the
request's context is cancelled once the handler returns. TS's built-in webhook handler
already responds `200 OK` *before* running your middleware chain (errors past that point
only reach `bot.catch()`, MAX will not retry). Neither SDK exposes a stable per-delivery
id or deduplicates for you. Build your own key from `update_type` + `timestamp`, plus
`message_id`/`comment_id`/`callback_id` when present, to drop retried webhook deliveries.

```go
import (
	"context"
	"fmt"
	"sync"

	maxbot "github.com/max-messenger/max-bot-api-client-go/v2"
	"github.com/max-messenger/max-bot-api-client-go/v2/model"
)

// FastAck detaches processing into a goroutine and drops duplicate
// deliveries. Swap the sync.Map for Redis/DB with a TTL in production.
func FastAck(process func(context.Context, model.Update)) maxbot.UpdateHandler {
	var seen sync.Map
	return func(ctx context.Context, u model.Update) {
		key := fmt.Sprintf("%s:%d:%s%s%s", u.UpdateType, u.Timestamp, u.MessageID, u.PostID, u.CommentID)
		if _, dup := seen.LoadOrStore(key, struct{}{}); dup {
			return
		}
		go process(context.WithoutCancel(ctx), u)
	}
}
```

```typescript
import type { Bot, Context, MiddlewareFn } from '@maxhub/max-bot-api';

// bot.webhookCallback()/createWebhook() already ack 200 before this chain
// runs; this middleware only adds duplicate-delivery filtering.
export function dedupe(): MiddlewareFn<Context> {
  const seen = new Set<string>();
  return async (ctx, next) => {
    const key = `${ctx.updateType}:${ctx.update.timestamp}:${ctx.messageId ?? ''}`;
    if (seen.has(key)) return;
    seen.add(key);
    if (seen.size > 10000) seen.clear(); // crude bound; use Redis+TTL for real traffic
    await next();
  };
}

export function wireWebhook(bot: Bot): void {
  bot.use(dedupe());
}
```

## Graceful shutdown

Stop accepting new updates, let in-flight handlers finish, then exit.

```go
import (
	"context"
	"net/http"
	"os/signal"
	"syscall"
	"time"

	maxbot "github.com/max-messenger/max-bot-api-client-go/v2"
)

func runWithGracefulShutdown(api *maxbot.Api, srv *http.Server) error {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	errCh := make(chan error, 1)
	go func() { errCh <- srv.ListenAndServe() }()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return srv.Shutdown(shutdownCtx)
	}
}
```

```typescript
import type { Bot } from '@maxhub/max-bot-api';

export function installGracefulShutdown(bot: Bot): void {
  const shutdown = async (signal: string) => {
    console.log(`received ${signal}, shutting down`);
    bot.stopPolling();
    await bot.stopWebhook();
    process.exit(0);
  };
  process.on('SIGINT', () => { void shutdown('SIGINT'); });
  process.on('SIGTERM', () => { void shutdown('SIGTERM'); });
}
```
