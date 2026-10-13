> Source: TS github.com/max-messenger/max-bot-api-client-ts@963ba4a (npm `@maxhub/max-bot-api`
> **0.3.1**) · verified 2026-09-21. If this looks outdated, check the repo's `CHANGELOG.md` and
> `docs/*.md` first — the public tutorial pages sometimes lag the package.

# TypeScript / JavaScript client (`@maxhub/max-bot-api`)

**Contents:** [Install and requirements](#install-and-requirements) · [Bot — constructor and options](#bot--constructor-and-options) · [bot.start() — polling or webhook](#botstart--polling-or-webhook) · [Composer / handler API](#composer--handler-api) · [Context](#context) · [Keyboards and buttons](#keyboards-and-buttons) · [Attachments and uploads](#attachments-and-uploads) · [Sessions and scenarios](#sessions-and-scenarios) · [Raw API escape hatch](#raw-api-escape-hatch) · [Errors, retries, rate limiting](#errors-retries-rate-limiting) · [Pitfalls](#pitfalls)

Official TS/JS bot framework for MAX. Covers Bot API access, update handling (`Composer`),
sessions, scenarios, and webhook hosting in one package.

## Install and requirements

- Package: `@maxhub/max-bot-api`, current version **0.3.1**. Ignore the git tag `v1.0.0` in the
  repo — it's a stale mis-tag (2026-06-24, `package.json` at that commit says `0.2.2`); go by the
  npm version.
- Requires **Node >= 20.19.0**.
- **ESM-only**: `exports` has no `require` condition. Import with `import`, not `require`; if
  your project is CommonJS, either switch to ESM or use a dynamic `import()`.
- Runtime deps: `debug`, `form-data`, `vcf`. No peer dependencies.
- Install: `npm install @maxhub/max-bot-api` (or `yarn add` / `pnpm add`).

## `Bot` — constructor and options

```typescript
import { Bot } from '@maxhub/max-bot-api';

const bot = new Bot(process.env.MAX_BOT_TOKEN ?? '');
```

`new Bot(token, config?)` — `config` is `Partial<{ clientOptions, contextType }>`:

| Option | Type | Notes |
|---|---|---|
| `clientOptions.baseUrl` | `string` | Default `https://platform-api2.max.ru`. The old host is present in source only as a commented-out `@deprecated` line — never set it. |
| `clientOptions.fetch` | `(input, init) => Promise<Response>` | Custom fetch for Bot API JSON calls only (`/me`, `/updates`, `/messages`, the `/uploads` URL-issuing call). Does **not** cover the raw-socket file-upload transport — see Attachments below. Use this to inject a CA-aware `fetch`; see `references/tls-trust.md`. |
| `contextType` | `new (...args) => Ctx` | Custom `Context` subclass, default `Context`. |

`Authorization` is a raw header equal to the token string — no `Bearer` prefix, no query param.
An empty token short-circuits locally to a synthetic 401 without a network call.

`bot.catch((err, ctx) => void)` overrides error handling; the default handler sets
`process.exitCode = 1`, logs, and rethrows — always set your own in production so one bad update
doesn't crash the process.

## `bot.start()` — polling or webhook

<!-- nocompile -->
```typescript
type StartConfig =
  | { mode: 'polling'; options?: { allowedUpdates?: UpdateType[]; retry?: boolean } }
  | { mode: 'webhook'; options: WebhookOptions & { allowedUpdates?: UpdateType[] } };
```

`mode` is a required discriminant on the *options object*, not a separate argument — a call like
`bot.start({ allowedUpdates: [...] })` with no `mode` key does not match this type and will not
compile under `strict` TypeScript, even though it appears in the package's own `showcase-bot.ts`
example. Always include `mode`.

- `bot.start()` with no argument means `{ mode: 'polling' }`.
- Before starting, `start()` always calls `api.getMyInfo()` to populate `botInfo` — a bad token
  fails fast here, before any handler runs.
- **Polling mode unconditionally clears every existing webhook subscription first**
  (`Webhook.clearSubscriptions`, no `activeUrl` filter). Switching a bot from webhook to polling
  silently drops any *other* webhook URLs registered on that token, not just your own.
- `retry` defaults to `true`: on an unhandled polling error the whole polling loop restarts after
  a flat 5s delay. Independently, the internal polling transport retries `429`/`5xx`/network
  errors with its own backoff (5s doubling to a 60s cap) before that outer restart ever triggers.
- `bot.stop()` is deprecated; use `bot.stopPolling()`.

### Webhook mode — three ways to run it

```typescript
import { Bot } from '@maxhub/max-bot-api';
import express from 'express';

const bot = new Bot(process.env.MAX_BOT_TOKEN ?? '');

// 1. Let the SDK own the HTTP server entirely.
async function runOwnServer(): Promise<void> {
  await bot.start({
    mode: 'webhook',
    options: {
      domain: process.env.PUBLIC_DOMAIN ?? 'https://example.com',
      port: 3000,
      secret: process.env.MAX_WEBHOOK_SECRET,
    },
  });
}

// 2. Mount a callback on your own server (Express, Fastify, plain node:http all work — it's the
//    raw (req, res) signature). This does NOT subscribe or clean up old subscriptions for you.
function mountOnExpress(app: express.Express): void {
  const handler = bot.webhookCallback({
    domain: process.env.PUBLIC_DOMAIN ?? 'https://example.com',
    secret: process.env.MAX_WEBHOOK_SECRET,
  });
  app.post('/webhook', (req, res) => handler(req, res));
  void bot.api.subscribe(
    'https://example.com/webhook',
    process.env.MAX_WEBHOOK_SECRET,
    undefined,
  );
}

// 3. Register the subscription for you, but you still own the HTTP server.
async function createThenMount(app: express.Express): Promise<void> {
  const handler = await bot.createWebhook({
    domain: process.env.PUBLIC_DOMAIN ?? 'https://example.com',
    secret: process.env.MAX_WEBHOOK_SECRET,
  });
  app.post('/webhook', (req, res) => handler(req, res));
}

void runOwnServer;
void mountOnExpress;
void createThenMount;
```

`WebhookOptions = { domain: string; port?: number /* default 3000 */; path?: string; secret?: string }`.
If `path` is omitted, one is generated from a hash of the token
(`/webhook/${sha256(token)}`) — stable across restarts, but effectively secret-by-obscurity only;
still set `secret` for a real check. `Webhook.getWebhookUrl` always forces `https://` regardless
of what you pass as `domain`.

The built-in HTTP handler only accepts `POST` to the exact hook path (`404` on everything else),
returns `400 Invalid JSON` on unparseable bodies, and — important — sends **`200 OK` to MAX
before running your middleware chain**. Errors thrown deep inside your handlers are caught and
only `debug()`-logged, not surfaced to MAX; by the time `bot.catch()` fires, MAX already got its
200 and will not retry. Enable `DEBUG=max:*` if webhook-driven updates seem to vanish silently.

For secret verification details (header name, timing-safe comparison, 404-on-mismatch) see
`references/webhooks-and-security.md` (all verification formulas with tested code).

## Composer / handler API

`Bot extends Composer<Ctx>`; all these methods are chainable (mutate the middleware chain):

| Method | Matches | Notes |
|---|---|---|
| `use(...middlewares)` | every update | Plain middleware append. |
| `on(filters, ...mw)` | `ctx.has(filters)` true | `filters` is an `UpdateType` string, a type-guard function, or an array of either; narrows `ctx` type. |
| `command(commands, ...mw)` | `message_created` text starting with `/` | Trigger receives the text *after* the leading slash (`/name value` → `"name value"`); sets `ctx.match`. |
| `hears(triggers, ...mw)` | `message_created` full-text match | String or `RegExp` trigger(s); sets `ctx.match`. |
| `action(triggers, ...mw)` | `message_callback` whose `callback.payload` matches | Sets `ctx.match`. |
| `filter(filters)` | — | Generic combinator `on`/`command`/`hears`/`action` build on. |
| `drop(predicate)` | stops the chain when `predicate` is true | |
| `fork(mw)` | runs concurrently with the rest of the chain | Either branch throwing makes `fork` throw. |
| `tap(mw)` | side effect, chain always continues | |
| `lazy(factory)` | resolves which middleware to run per update | |
| `branch(predicate, onTrue, onFalse)` | exactly one branch runs | Each branch controls whether to call `next()`. |
| `dispatch(route, handlers, fallback?)` | picks a handler by `route(ctx)`'s return key | |
| `help(...mw)` / `settings(...mw)` | shorthand for `command('help', ...)` / `command('settings', ...)` | |

`anyOf(...filters)` / `allOf(...filters)` combine `UpdateType`/guard filters with OR/AND
semantics and are exported from the package root, usable in `.on()`/`.filter()`.

```typescript
import { Bot, anyOf } from '@maxhub/max-bot-api';

const bot = new Bot(process.env.MAX_BOT_TOKEN ?? '');

bot.command('start', (ctx) => ctx.reply('Welcome!'));
bot.hears('hello', (ctx) => ctx.reply('world'));
bot.on(anyOf('message_created', 'message_callback'), (ctx, next) => {
  ctx.state.interactive = true;
  return next();
});
bot.action(/^buy:\d+$/, async (ctx) => {
  await ctx.answerOnCallback({ message: { text: 'Added to cart' } });
});
```

## `Context`

Constructed per update as `new Context(update, api, botInfo?)`, all three stored as readonly
public fields.

Key fields: `match` (set by `command`/`hears`/`action`), `state` (per-update scratch object,
discarded after), `updateType`, `myId` (bot's own `user_id`), `startPayload` (deep-link payload
on `bot_started`), `chat`, `chatId`, `message`, `messageId`, `callback`, `user`, plus lazily
computed `contactInfo`/`location`/`sticker` parsed from the matching attachment type.

Key methods (each a thin wrapper over the matching `Api` call, using `ctx.chatId`/`ctx.messageId`
where required): `reply(text, extra?)`, `getAllChats(extra?)` (wraps `GET /chats`, removed by the platform in 2026-06 — expect an error; track chats from updates instead, see `patterns.md`), `getChat(chatId?)`, `getMessage(id)`,
`editMessage(extra)`, `deleteMessage(messageId?)`, `answerOnCallback(extra)`, `pinMessage(id, extra?)`,
`getChatMembers(extra?)`, `addChatMembers(userIds)`, `removeChatMember(userId)`, `sendAction(action)`,
`leaveChat()`, `getComments(messageId, extra?)`, `deleteComment(messageId, commentId)`.
`has(filters)` is the runtime type guard backing `.on()`. `assert(value, method)` throws when a
chat/message-scoped method is called on an update that doesn't have one.

## Keyboards and buttons

```typescript
import { Bot, Keyboard } from '@maxhub/max-bot-api';

const bot = new Bot(process.env.MAX_BOT_TOKEN ?? '');

bot.command('menu', (ctx) =>
  ctx.reply('Choose one:', {
    attachments: [
      Keyboard.inlineKeyboard([
        [Keyboard.button.callback('Option A', 'opt:a'), Keyboard.button.callback('Option B', 'opt:b')],
        [Keyboard.button.link('Docs', 'https://dev.max.ru/docs-api')],
      ]),
    ],
  }),
);
```

Real button builders in `Keyboard.button`: `callback(text, payload)`, `clipboard(text, payload)`,
`link(text, url)`, `requestContact(text)`, `requestGeoLocation(text, extra?)`, `message(text)`,
`openApp(text, webApp, contactId?, payload?)` — 7 functions total.

`Keyboard.button.clipboard` exists in source but isn't documented on the public site or in the
package's own `docs/04-keyboard.md` — it works, just don't expect to find it in the prose docs.

`docs/04-keyboard.md` also documents a `button.chat(text, chatTitle, extra?)` helper ("creates a
chat"). **It does not exist in the 0.3.1 source** (`src/helpers/buttons.ts` exports exactly the
7 functions above, no `chat`) — the live public site's button-type list independently confirms
only 6 named button types plus the undocumented `clipboard`, with no `chat` type either. Do not
use `button.chat`; treat it as stale/planned-but-unshipped documentation until a newer release
proves otherwise.

## Attachments and uploads

```typescript
import { Bot } from '@maxhub/max-bot-api';

const bot = new Bot(process.env.MAX_BOT_TOKEN ?? '');

bot.command('photo', async (ctx) => {
  const image = await ctx.api.uploadImage({ url: 'https://example.com/pic.jpg' });
  await ctx.reply('', { attachments: [image.toJson()] });
});
```

- `ctx.api.uploadImage/uploadVideo/uploadAudio/uploadFile({source})` upload a new file and return
  the matching `Attachment` instance wrapping the returned token; `ImageAttachment` alone also
  accepts `{url}` for upload-by-URL (image-only, per the docs).
- To resend an already-uploaded file by token: `new ImageAttachment({token})` (and the
  `Video`/`Audio`/`File` equivalents), then pass `.toJson()` in `attachments`.
- Non-uploaded attachment types are built client-side: `StickerAttachment({code})`,
  `LocationAttachment({lon, lat})`, `ShareAttachment({url?, token?})`.
- Internally, uploads go through `getUploadUrl({type})` then either a resumable chunked upload
  (if a `token` came back immediately) or a single multipart POST. This is upload-host and
  transport detail (see `references/bot-api.md` and `references/tls-trust.md`) — the point here is
  that **`clientOptions.fetch` does not see any of it**: the actual file bytes travel over a
  separate raw `node:http`/`https` transport with no `fetch`/CA hook at all.
- `attachment.not.ready`: `MessagesApi.send` (used by `ctx.reply`/`api.sendMessageToChat`, etc.)
  retries this specific error automatically, up to 3 times with 1s/2s/4s backoff, aborting early
  on your own `AbortSignal`. Any other error is rethrown immediately, unretried. The upload call
  itself (`Upload.image/video/audio/file`) has zero built-in retry.

## Sessions and scenarios

Three tiers of state: `ctx.state` (this update only), `ctx.session` (per user+chat, persists
across updates via a store), and your own application database.

```typescript
import { Bot, Context, MemorySessionStore, session } from '@maxhub/max-bot-api';

interface CartSession {
  items: string[];
}

type CartContext = Context & { session: CartSession };

const bot = new Bot<CartContext>(process.env.MAX_BOT_TOKEN ?? '');

bot.use(
  session<CartSession, CartContext>({
    store: new MemorySessionStore<CartSession>(60 * 60 * 1000),
    defaultSession: () => ({ items: [] }),
  }),
);

bot.command('cart', (ctx) => ctx.reply(`Items: ${ctx.session.items.length}`));
```

The two type parameters on `session<S, C>` are both required — TypeScript cannot infer `C`
(your custom `Context` subtype) from the options object alone, so pass it explicitly, matching
`new Bot<C>(...)`, or the call fails to compile with "Expected 2-3 type arguments."

`session(options?)`: `property` (default `'session'`), `getSessionKey` (default
`<user_id>:<chat_id>`; returning nullish skips session creation), `store` (default
`MemorySessionStore`), `defaultSession`. **`MemorySessionStore` is in-process only — every session
and every in-flight scenario is lost on restart, crash, or redeploy.** Don't recommend sessions or
scenarios in the skill without this caveat; supply your own `SessionStore` (Redis, SQL, etc.) —
`get`/`set`/`delete`, sync or async — for anything that must survive a deploy.

Scenarios (`defineScenario`, `ScenarioEngine`, `transition`) are a thin routing layer over
`session`, tracking `{id, step, data, expiresAt?}`. Each step handler receives a **frozen, cloned**
snapshot of `state`/`data` — mutating it in place is a silent no-op; return
`transition.goto(step, data)` / `transition.stay(data)` to persist changes.
`interceptMiddleware()` routes an update to the active scenario step if one is running; expired
scenarios are deleted and fall through to the rest of the chain. Recommended wiring order:
`session()` → `scenarios.controllerMiddleware()` → global commands (`/help`, `/cancel`) →
`scenarios.interceptMiddleware()` → scenario-starting commands, so global commands can still
"escape" an active scenario.

## Raw API escape hatch

`ctx.api.raw` (and `bot.api.raw`) exposes generic HTTP verbs plus per-resource module getters
(`chats`, `bots`, `messages`, `subscriptions`, `uploads`, `comments`). **At 0.3.1, `RawApi` only
publicly exposes `get`, `post`, and `patch`** — `put`/`delete` exist internally on the base class
but are not re-exposed as public methods on `RawApi`, even though both the package's own
`docs/02-listen-and-respond.md` and the live public site show `ctx.api.raw.put(...)` /
`.delete(...)` as available. Don't assume those two compile; use the typed `Api` wrapper methods
(`ctx.deleteMessage()`, `ctx.editMessage()`, etc.) instead, or re-verify against a newer tag
before relying on `raw.put`/`raw.delete`.

```typescript
import { Bot } from '@maxhub/max-bot-api';

const bot = new Bot(process.env.MAX_BOT_TOKEN ?? '');

bot.command('raw', async (ctx) => {
  // Generic shape: method string with {param} placeholders + query/body/path.
  const info = await ctx.api.raw.get('me', {});
  await ctx.reply(JSON.stringify(info));
});
```

## Errors, retries, rate limiting

`MaxError extends Error` — `{status, code, message}`; thrown for **any** non-200 response from
`client.call`, so every raw/high-level API method can throw one.

**No generic retry and no client-side rate limiting anywhere in the JSON client** — every call is
a single `fetch`. The only two built-in retry behaviors are (a) `attachment.not.ready` on message
send, 3 attempts / 1s-2s-4s backoff, and (b) long-polling `getUpdates` backoff on `429`/`5xx`/
network errors, 5s doubling to a 60s cap. Everything else — chats, comments, subscriptions,
uploads, webhook delivery — is a single unretried attempt. The 30 rps platform limit is entirely
your own responsibility to enforce; see `references/patterns.md` for a token-bucket recipe.

## Pitfalls

| Pitfall | Detail |
|---|---|
| `bot.start({allowedUpdates:[...]})` with no `mode` | Does not match `StartConfig`; won't compile under `strict` TS even though it appears in the SDK's own `showcase-bot.ts`. Always include `mode: 'polling' \| 'webhook'`. |
| `bot.webhookCallback()` alone | Does not subscribe or clear old subscriptions — you can stand up a server that never receives traffic because nothing called `bot.api.subscribe`. Use `bot.createWebhook()` if you want registration handled for you but still own the HTTP server. |
| `MemorySessionStore` in production | In-memory only; every session/scenario is lost on restart. Plug in a real store before shipping. |
| `clientOptions.fetch` and uploads | Only covers Bot API JSON calls; the raw file-upload transport is untouched — a CA-aware custom fetch will not help uploads (uploads hosts don't need the extra CA anyway, see `references/tls-trust.md`). |
| Assuming `ctx.api.raw.put`/`.delete` compile | They don't at 0.3.1 despite being shown in the docs; use the typed `Api`/`Context` methods. |
| `button.chat` from `docs/04-keyboard.md` | Not implemented in 0.3.1 or listed on the site — don't use it. |
| Trusting a webhook 200 as "handled successfully" | The SDK answers MAX with 200 before your middleware chain runs; errors inside it are only debug-logged, not retried by MAX. |
| `ctx.answerOnCallback({ notification: '...' })` | The package's own `examples/showcase-bot.ts` uses a `notification` field, but the shipped `AnswerOnCallbackExtra` type (0.3.1) only declares `message?`. The Bot API itself does support a `notification` toast (see `references/bot-api.md`'s `POST /answers` body), so this is a TS-type omission, not a missing feature — use `{ message: { text: '...' } }` to edit the message, or pass `notification` with a type assertion (`{ notification: '...' } as AnswerOnCallbackExtra & { notification?: string }`) if you need the toast and are willing to work around the gap. |
