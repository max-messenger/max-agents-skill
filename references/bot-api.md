> Source: DOCS https://dev.max.ru/docs-api + SCHEMA github.com/max-messenger/api-schema@1a4a502 · verified 2026-09-21. If anything here looks outdated, check those first.

# Bot API reference

## Base URL and auth

Base URL: `https://platform-api2.max.ru`. Mandatory since 19 July 2026 (was `platform-api.max.ru`). Requesting the old host is not guaranteed to keep working — no shutdown date is published, but new integrations must use `platform-api2.max.ru`. This host requires the Russian Trusted Root CA in your HTTP client's trust store — see `tls-trust.md` for setup per language/runtime.

Auth: send the raw bot token in the `Authorization` header, no `Bearer` prefix. Passing the token as a query parameter is not supported.

```bash
curl -X GET "https://platform-api2.max.ru/me" \
  -H "Authorization: $MAX_BOT_TOKEN"
```

## Rate limits

| Scope | Limit |
|---|---|
| `platform-api2.max.ru`, all endpoints | 30 requests/second |
| `POST /answers` | ≤2 answers/second per dialog/chat/channel |
| Long polling (`GET /updates`) | 300ms minimum interval between calls |

Note: the docs give 30 rps without saying whether it is per bot token or platform-wide. Design for at most 30 rps per bot token.

## Endpoint table

All paths relative to the base URL. There is no `GET /chats` (list) endpoint — see Dated changes.

| Method | Path | Query params | Body | Response | Purpose |
|---|---|---|---|---|---|
| GET | `/me` | — | — | BotInfo | Get current bot info |
| PATCH | `/me/commands` | — | BotCommandsPatch | BotCommandsInfo | Edit bot commands |
| GET | `/chats/{chatId}` | — | — | Chat | Get chat/channel info |
| PATCH | `/chats/{chatId}` | — | ChatPatch | Chat | Edit chat/channel info |
| POST | `/chats/{chatId}/actions` | — | ActionRequestBody | SimpleQueryResult | Send bot action (typing, etc.) |
| GET | `/chats/{chatId}/pin` | — | — | GetPinnedMessageResult | Get pinned message |
| PUT | `/chats/{chatId}/pin` | — | PinMessageBody | SimpleQueryResult | Pin message |
| DELETE | `/chats/{chatId}/pin` | — | — | SimpleQueryResult | Unpin message |
| GET | `/chats/{chatId}/members/me` | — | — | ChatMember | Get bot's own membership |
| DELETE | `/chats/{chatId}/members/me` | — | — | SimpleQueryResult | Leave chat |
| GET | `/chats/{chatId}/members/admins` | — | — | ChatMembersList | Get admins |
| POST | `/chats/{chatId}/members/admins` | — | ChatAdminsList | SimpleQueryResult | Set admins (full replace, despite POST verb) |
| DELETE | `/chats/{chatId}/members/admins/{userId}` | — | — | SimpleQueryResult | Revoke admin rights |
| GET | `/chats/{chatId}/members` | `user_ids`, `marker`, `count` (1-100, default 20) | — | ChatMembersList | Get members |
| POST | `/chats/{chatId}/members` | — | UserIdsList (≤100 ids) | ModifyMembersResult | Add members — **do not use, see Dated changes** |
| DELETE | `/chats/{chatId}/members` | `user_id` (required), `block` (bool, default `false`) | — | SimpleQueryResult | Remove member |
| GET | `/subscriptions` | — | — | GetSubscriptionsResult | List webhook subscriptions |
| POST | `/subscriptions` | — | SubscriptionRequestBody | SimpleQueryResult | Subscribe to webhook |
| DELETE | `/subscriptions` | `url` (required) | — | SimpleQueryResult | Unsubscribe |
| POST | `/uploads` | `type` (required: `image`\|`video`\|`audio`\|`file`) | binary (multipart or resumable) | UploadEndpoint | Get upload URL/token |
| GET | `/messages` | `chat_id`, `message_ids`, `from`/`to` (deprecated), `before`, `after`, `count` (1-100, default 50) | — | MessageList | Get messages (reverse chronological) |
| POST | `/messages` | `user_id`, `chat_id`, `disable_link_preview` (bool, default `false`) | NewMessageBody | SendMessageResult | Send message |
| PUT | `/messages` | `message_id` (required) | NewMessageBody | SimpleQueryResult | Edit message |
| DELETE | `/messages` | `message_id` (required) | — | SimpleQueryResult | Delete message |
| GET | `/messages/{messageId}` | — | — | Message | Get single message |
| GET | `/messages/{messageId}/comments` | `comment_ids`, `before`, `after`, `count` (1-100, default 50) | — | CommentMessageList | Get comments on a post |
| POST | `/messages/{messageId}/comments` | `disable_link_preview` | NewCommentBody | SendCommentResult | Send comment (no attachments) |
| PUT | `/messages/{messageId}/comments` | `comment_id` (required) | NewCommentBody | SimpleQueryResult | Edit comment |
| DELETE | `/messages/{messageId}/comments` | `comment_id` (required) | — | SimpleQueryResult | Delete comment |
| GET | `/messages/{messageId}/comments/{commentId}` | — | — | CommentMessage | Get single comment |
| GET | `/videos/{videoToken}` | — | — | VideoAttachmentDetails | Get video playback URLs/metadata |
| POST | `/answers` | `callback_id` (required, non-empty), `disable_link_preview` | CallbackAnswer | SimpleQueryResult | Answer a button-press callback |
| GET | `/updates` | `limit` (1-1000, default 100), `timeout` (0-90s, default 30), `marker` (nullable int64), `types` (csv) | — | UpdateList | Long-poll for updates |

### Params that are QUERY, not body — common mistakes

- `disable_link_preview` is a **query** param on `POST /messages`, `POST /messages/{messageId}/comments`,
  and `POST /answers` only — `PUT /messages` and `PUT .../comments` accept no such param. It is **not**
  a field of `NewMessageBody`/`NewCommentBody`/`CallbackAnswer.message`.
- `message_id` (edit/delete message), `comment_id` (edit/delete comment), `callback_id` (`POST /answers`), `url` (`DELETE /subscriptions`), `user_id`+`block` (`DELETE /chats/{chatId}/members`) are all query params, not body fields.
- `user_id` / `chat_id` on `POST /messages` are query params that select the recipient; the recipient is never part of `NewMessageBody`.

### Notable per-endpoint behavior

- `PUT /messages` (edit): `attachments: null` in the body keeps existing attachments, `attachments: []` clears them.
- `DELETE /messages`, `PUT`/`DELETE .../comments` require the bot to hold the `delete`/`edit`/`write` admin permission (see `objects-and-updates.md` → ChatAdminPermission), which itself requires `read_all_messages`.
- `POST /chats/{chatId}/members/admins` behaves like a full-replace `PUT` despite the HTTP verb: repeat calls fully overwrite the admin's permission set.
- Comments (`/messages/{messageId}/comments/*`) are channel-only, added August 2026, and never carry attachments or a public `url`.

## Upload flow (all media attachment types)

Three steps, identical shape for `image`/`video`/`audio`/`file`:

1. `POST /uploads?type={image|video|audio|file}` → `UploadEndpoint {url, token?}`.
2. Upload the binary to the returned `url` — **not** a fixed host; the URL from the response is the only valid destination for that upload. Two transport modes: **multipart** (`Content-Type: multipart/form-data`, single request) or **resumable** (any other/no `Content-Type`; supports `Content-Range` for chunked upload/resume — `GET` on the upload URL returns current status; `REQUESTED_RANGE_NOT_SATISFIABLE` or `INTERNAL_SERVER_ERROR` mean restart).
3. Attach the resulting `{type, payload}` object to the message/comment.

```bash
curl -X POST "https://platform-api2.max.ru/uploads?type=video" \
  -H "Authorization: $MAX_BOT_TOKEN"
```

```json
{"url": "https://<upload-host>/upload.do?..."}
```

```bash
curl -i -X POST -H "Content-Type: multipart/form-data" \
  -F "data=@movie.mp4" "https://<upload-host>/upload.do?..."
```

```json
{"token": "<upload-token>"}
```

```json
{
  "text": "Message with video",
  "attachments": [
    {"type": "video", "payload": {"token": "<upload-token>"}}
  ]
}
```

Notes:
- Upload hosts vary by type and are not stable, documented values to hardcode — always use the `url` returned by `POST /uploads` for that request. Do not assume a fixed hostname per type.
- Images can skip `/uploads` entirely: pass an external `url` directly in the request's `PhotoAttachmentRequestPayload.url`. Other media types have no such shortcut.
- One file per upload URL — call `POST /uploads` again for each new file. The URL itself has no stated expiry, but is single-use.
- `type=photo` is no longer accepted; use `type=image`.
- Exact timing of when `token` becomes available (at step 1 vs. only after step 2) differs by type in DOCS' own wording and is internally inconsistent for video/audio vs. image/file — don't rely on `token` being present before you've confirmed it in the actual response you received.
- `attachment.not.ready` error: server hasn't finished processing the uploaded media yet. Returned as `{"code": "attachment.not.ready", "message": "Key: errors.process.attachment.file.not.processed"}` on the *send message* call, as a `400`. Mitigate by retrying the send with backoff, or by pre-uploading and reusing tokens for frequently-sent files.

## Attachment combination rules

Only one rule set is authoritative (DOCS; the schema's per-type "must be the only attachment" wording is superseded for `file` — see `objects-and-updates.md`):

- `image` + `video`: combinable with each other and with **at most 1** `inline_keyboard` attachment. Total media attachments (image+video) in one message: **≤12**.
- `file`: combinable with **at most 1** `inline_keyboard` attachment only — never with `image`/`video`/other `file`. Exactly one `file` per message.
- `audio`, `contact`, `sticker`: each must be the only attachment in the message (no keyboard, no other media) — schema wording, no DOCS counter-example found.
- `location`, `share`: not covered by the DOCS combination table; treat as single-attachment unless you verify otherwise against a live send.

Valid combination examples from DOCS: 6 video + 5 image + 1 inline_keyboard; 12 video; 12 image; 11 video + 1 inline_keyboard; 11 image + 1 inline_keyboard; 6 video + 6 image; 1 file + 1 inline_keyboard.

## Limits

| Limit | Value |
|---|---|
| Message/comment text length | 4000 characters of the raw `text` string — every character counts: any alphabet, digits, spaces, line breaks, emoji, and markdown/HTML markup symbols. Characters, not bytes (Cyrillic is 2 bytes in UTF-8 but 1 character here) |
| Chat title | 1-200 chars |
| Button text | 1-128 chars |
| `CallbackButton.payload` / `ClipboardButton.payload` | ≤1024 chars |
| `LinkButton.url` | ≤2048 chars |
| `LinkMarkup.url` (response markup) | 1-2048 chars |
| `OpenAppButton.payload` | ≤512 chars, pattern `^[\w-]*$` |
| Deeplink `start=` payload (bot link) | ≤128 chars — longer is dropped, never reaches the bot |
| Deeplink `startapp=` payload (mini-app link) | ≤512 chars, allowed chars `A-Za-z0-9_-` |
| `BotCommand.name` | 1-64 chars |
| `BotCommand.description` | 1-128 chars |
| Bot commands count | ≤32 |
| `UserIdsList` (add members) | ≤100 ids/request |
| `GET /messages`, `.../comments` `count` | 1-100, default 50 |
| `GET /chats/{chatId}/members` `count` | 1-100, default 20 |
| `GET /updates` `limit` | 1-1000, default 100 |
| `GET /updates` `timeout` | 0-90s, default 30 |
| Long polling minimum interval | 300ms |
| Webhook secret | 5-256 chars, `^[\w-]+$` (A-Z a-z 0-9 _ -) |
| Webhook response timeout | must return HTTP 200 within 30s |
| Webhook retry count | up to 10, exponential ×2.5 (60s, 150s, 375s, …) |
| Webhook auto-unsubscribe | after 8h with no successful (200) delivery |
| Webhook port | 443 only |
| `POST /answers` rate | ≤2/sec per dialog/chat/channel |
| Global API rate | 30 rps on `platform-api2.max.ru` |
| Image size | ≤50MB **and** ≤7680×7680px (both required) |
| Video size | ≤250MB |
| Audio size | ≤256MB **and** ≤60min (both required) |
| File size | ≤4GB |
| Keyboard | ≤210 buttons total, ≤30 rows, ≤7 per row (≤3 for `link`/`open_app`/`request_geo_location`/`request_contact`) — DOCS only, not schema-enforced (no `maxItems` on `Keyboard.buttons`); server rejects violations even though a schema-only validator would allow them |
| Media combination cap | ≤12 image+video attachments per message; `file` combinable only with 1 keyboard (see above) |
| `InlineKeyboardAttachmentRequestPayload.buttons` | `minItems: 1` (schema-enforced) |
| Bots per legal-entity/IP profile | 5 |
| Bots per self-employed (самозанятый) profile | 2 |
| Bot nickname length | 11-60 chars |
| Public channels (verified legal entities/IP) | 10 |

Note: `start=` (bot) and `startapp=` (mini-app) are different links with different caps — 128 and 512. The schema field `BotStartedUpdate.payload` allows up to 512 characters, but that is only the field's width; bot `start=` links still cap at 128.

## Errors

### HTTP status codes
`200` success, `400` invalid request, `401` authentication error, `403` forbidden, `404` not found, `405` method not allowed, `429` rate limit exceeded, `500` internal error, `503` service unavailable.

Note: DOCS' top-level overview page omits 403 from its summary list, but individual method pages (e.g. `PATCH /chats/{chatId}`, `POST /chats/{chatId}/members`) and the schema both use it — treat 403 as real and handle it.

### Generic error shape
```json
{"code": "chat.denied", "message": "Forwarding messages from this chat or channel is prohibited"}
```
`code` and `message` are required; an optional `error` field sometimes appears.

### Named error codes actually documented
There is no single canonical error-code list in either SCHEMA or DOCS — only these are documented; don't present this as exhaustive:

| Code | Meaning |
|---|---|
| `chat.denied` | Forwarding from this chat/channel is prohibited (403 on `POST /messages`) |
| `attachment.not.ready` | Media not yet processed server-side (see Upload flow) |
| `add.participant.privacy` | Privacy settings blocked adding a participant |
| `add.participant.not.found` | User(s) to add not found |
| `File extension is forbidden` | Unsupported upload file extension (raw message string, not a formal `code`) |

