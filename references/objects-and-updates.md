> Source: DOCS https://dev.max.ru/docs-api + SCHEMA github.com/max-messenger/api-schema@1a4a502 · verified 2026-09-21. If anything here looks outdated, check those first.

# Objects and updates reference

Field lists below are from `schema.yaml`. `nullable`/optional fields are marked; unmarked fields are required.

## Message bodies (request)

### NewMessageBody (`POST`/`PUT /messages` body)
| Field | Type | Notes |
|---|---|---|
| `text` | string, nullable | max 4000 chars |
| `attachments` | AttachmentRequest[], nullable | see below; combination rules in `bot-api.md` |
| `link` | NewMessageLink, nullable | forward/reply |
| `notify` | bool | default `true` |
| `format` | `markdown`\|`html`, nullable | see `formatting.md` |

`NewMessageLink`: `type` (`forward`\|`reply`, required) + `mid` (message id, required).

### NewCommentBody (`POST`/`PUT .../comments` body)
Same shape minus `attachments` and `notify`: `text` (nullable, max 4000), `link` (NewMessageLink, nullable), `format`. Attachments are never allowed in comments.

## Message objects (response)

### Message
| Field | Type | Notes |
|---|---|---|
| `sender` | User, nullable | `null` if posted as a channel |
| `recipient` | Recipient | required |
| `timestamp` | int64 | required |
| `link` | LinkedMessage, nullable | |
| `body` | MessageBody | required |
| `stat` | MessageStat, nullable | channel-only, `{views}` |
| `url` | string, nullable | |

### MessageBody
`mid` (string, required), `seq` (int64, required), `text` (string, nullable), `attachments` (Attachment[], nullable), `markup` (MarkupElement[], nullable).

### Recipient
`chat_id` (nullable), `chat_type` (ChatType, required), `user_id` (nullable), `post_id` (nullable — comments only).

### CommentMessage / CommentMessageBody
Mirrors `Message`/`MessageBody` but drops `attachments` and public `url`. `recipient` on a comment is channel-only. `stat` — views, only in `GET /messages` context.

### MessageStat
`{views: int}`, required.

## Attachments — response (`Attachment`, discriminator `type`)

| `type` | Schema | Payload fields |
|---|---|---|
| `image` | PhotoAttachment | `photo_id` (int64), `token`, `url` — all required |
| `video` | VideoAttachment | `url`+`token` (MediaAttachmentPayload) + `thumbnail`, `width`, `height`, `duration` (sec), all nullable |
| `audio` | AudioAttachment | MediaAttachmentPayload + `transcription` (nullable) |
| `file` | FileAttachment | FileAttachmentPayload (`url`+`token`) + `filename` + `size` (bytes) — all required |
| `sticker` | StickerAttachment | `code` + `width` + `height` — all required |
| `contact` | ContactAttachment | `vcf_info` (nullable), `hash` (nullable), `max_info` (User, nullable) |
| `inline_keyboard` | InlineKeyboardAttachment | `Keyboard{buttons}` |
| `share` | ShareAttachment | `url`+`token` (nullable) + `title`, `description`, `image_url` (all nullable) |
| `location` | LocationAttachment | `latitude`, `longitude` (double, both required) — no payload wrapper |

`GET /videos/{videoToken}` → `VideoAttachmentDetails`: `token`, `urls` (nullable — `mp4_1080/720/480/360/240/144` + `hls`), `thumbnail` (nullable), `width`, `height`, `duration` (all required except `urls`/`thumbnail`).

## Attachments — request (`AttachmentRequest`, discriminator `type`)

Types: `image, video, audio, file, sticker, contact, inline_keyboard, location, share`.

- `PhotoAttachmentRequestPayload`: **mutually exclusive** — `url` (external image URL), `token` (existing attachment token), `photos` (map of `PhotoToken{token}` from upload).
- `video` / `audio` / `file`: `UploadedInfo{token}` payload only.
- `ContactAttachmentRequestPayload`: `name`, `contact_id` (UserId), `vcf_info`, `vcf_phone` — all nullable/optional.
- `InlineKeyboardAttachmentRequestPayload.buttons`: `minItems: 1` (schema-enforced — at least one row).
- Schema description text states `audio`, `file`, `contact`, `sticker` requests "MUST be the only attachment in message". DOCS' combination table contradicts this for `file` (file + 1 inline_keyboard is a valid, documented combination). Follow the combination rules in `bot-api.md`, not this schema wording, for `file`; treat "only attachment" as still authoritative for `audio`/`contact`/`sticker` since DOCS gives no counter-example for those.
- `UploadType` enum (for `POST /uploads?type=`): `image | video | audio | file` — no `photo` (removed, see `bot-api.md`).

## Buttons (`Button`, discriminator `type`)

Base `Button`: `type` + `text` (string, 1-128 chars) — both required.

| `type` | Schema | Extra fields |
|---|---|---|
| `callback` | CallbackButton | `payload` (string, ≤1024, required) |
| `link` | LinkButton | `url` (string, ≤2048, required) |
| `message` | MessageButton | none beyond base |
| `request_contact` | RequestContactButton | none beyond base |
| `request_geo_location` | RequestGeoLocationButton | `quick` (bool, default `false` — skip user confirmation) |
| `open_app` | OpenAppButton | `payload` (nullable, pattern `^[\w-]*$`, ≤512), `web_app` (string, **required** — public bot name wired to the mini app), `contact_id` (UserId, nullable) |
| `clipboard` | ClipboardButton | `payload` (string, ≤1024, required) |

`Keyboard`: `{buttons: Button[][]}` — two-dimensional array (rows of buttons), required. Row/button-count caps (210/30/7/3) are DOCS-only, not schema-enforced — see `bot-api.md` limits table.

```json
{
  "type": "inline_keyboard",
  "payload": {
    "buttons": [
      [{"type": "callback", "text": "Confirm", "payload": "confirm"}]
    ]
  }
}
```

## Update (19 `update_type` values, discriminator `update_type`)

| `update_type` | Schema | Key fields |
|---|---|---|
| `message_created` | MessageCreatedUpdate | `message` (req), `user_locale` (nullable, dialogs only) |
| `message_callback` | MessageCallbackUpdate | `callback` (req), `message` (nullable — may be gone if deleted), `user_locale` (nullable) |
| `message_edited` | MessageEditedUpdate | `message` (req) |
| `message_removed` | MessageRemovedUpdate | `message_id`, `chat_id`, `user_id` (all req) |
| `comment_created` | CommentCreatedUpdate | `message` (req — typed `Message`, not `CommentMessage`, in schema) |
| `comment_edited` | CommentEditedUpdate | `message` (req) |
| `comment_removed` | CommentRemovedUpdate | `message_id`, `chat_id`, `user_id`, `post_id` (all req) |
| `bot_added` | BotAddedToChatUpdate | `chat_id`, `user`, `is_channel` (all req) |
| `bot_removed` | BotRemovedFromChatUpdate | `chat_id`, `user`, `is_channel` (all req) |
| `user_added` | UserAddedToChatUpdate | `chat_id`, `user`, `is_channel` (req), `inviter_id` (nullable) |
| `user_removed` | UserRemovedFromChatUpdate | `chat_id`, `user`, `is_channel` (req), `admin_id` (optional) |
| `bot_started` | BotStartedUpdate | `chat_id`, `user` (req), `payload` (nullable, max 512 — deeplink `start` payload), `user_locale` |
| `bot_stopped` | BotStoppedUpdate | `chat_id`, `user` (req), `user_locale` |
| `dialog_cleared` | DialogClearedUpdate | `chat_id`, `user` (req), `user_locale` |
| `dialog_removed` | DialogRemovedUpdate | `chat_id`, `user` (req), `user_locale` |
| `dialog_muted` | DialogMutedUpdate | `chat_id`, `user`, `muted_until` (int64, req), `user_locale` |
| `dialog_unmuted` | DialogUnmutedUpdate | `chat_id`, `user` (req), `user_locale` |
| `chat_title_changed` | ChatTitleChangedUpdate | `chat_id`, `user`, `title` (all req) |
| `bot_admin_permissions_changed` | BotAdminPermissionsChangedUpdate | `chat_id`, `user_id`, `bot_id`, `is_channel`, `is_admin` (all req), `permissions` (nullable array) |

Note: comment-related update types (`comment_created`, `comment_edited`, `comment_removed`) were added August 2026 alongside the comments API.

### Callback / CallbackAnswer
- `Callback` (payload of `message_callback`): `timestamp`, `callback_id`, `user` (all required), `payload` (string, required by schema — may be empty for `message`/`request_contact` buttons which carry no payload).
- `CallbackAnswer` (body of `POST /answers`): `message` (NewMessageBody, nullable — fill to edit the original message), `notification` (string, nullable — one-time toast). Both optional, can combine.

## Chat / ChatMember / User

### Chat
`chat_id`, `type` (ChatType: `dialog`\|`chat`\|`channel`), `status` (ChatStatus: `active`\|`removed`\|`left`\|`closed`\|`suspended` — `suspended` is dialog-only), `title` (nullable), `icon` (`{url}`, nullable), `last_event_time`, `participants_count` (always 2 for dialogs), `owner_id` (nullable, admin-only visibility), `participants` (map user_id→last-activity, admin-only, nullable), `is_public` (always `false` for dialogs), `link` (nullable), `description` (nullable), `dialog_with_user` (UserWithPhoto, dialog-only, nullable), `messages_count` (nullable, not available for dialogs), `pinned_message` (Message, nullable, only on single-chat `GET`).

### ChatPatch (`PATCH /chats/{chatId}` body)
`icon` (PhotoAttachmentRequestPayload, nullable), `title` (1-200 chars, nullable), `description` (≤16000 chars, nullable — empty string removes it, added August 2026), `pin` (message id, nullable — use `DELETE /pin` to unpin instead), `notify` (bool, default `true`).

### User
`user_id`, `first_name`, `is_bot` (required); `last_name`, `username`, `last_activity_time` (nullable).

### UserWithPhoto (extends User)
Adds `description` (≤16000, nullable), `avatar_url`, `full_avatar_url` (nullable).

### ChatMember (extends UserWithPhoto)
Adds `last_access_time`, `is_owner`, `is_admin`, `join_time` (all required), `permissions` (ChatAdminPermission[], nullable), `alias` (nullable).

### ChatAdminPermission (11 values)
`read_all_messages, add_remove_members, add_admins, change_chat_info, pin_message, edit_link, write, edit, delete, can_call, view_stats`.

Note: `edit`/`delete`/`write`/`pin_message` require `read_all_messages` granted together or already present, else the server errors. Legacy response synonyms: `edit_message`→`edit`, `delete_message`→`delete`, `post_edit_delete_message`→`write` (use the new names when assigning permissions). `add_remove_members` works for bots only in chats, not channels. `can_call` and `view_stats` cannot be assigned manually (auto/owner-only). This permission-semantics text is DOCS-only, not in the schema.

## Comments-related objects

`NewCommentBody`, `CommentMessage`, `CommentMessageBody` — see above. `SendCommentResult`: `{message: CommentMessage}`, required. `CommentMessageList`: `{messages: CommentMessage[]}`, required.

## MarkupElement (response-side text markup, 10 types)

Base: `type`, `from` (int32, start index), `length` (int32) — all required. Types: `strong`, `emphasized`, `monospaced`, `link`, `strikethrough`, `underline`, `user_mention`, `heading`, `highlighted`, `quote`.

- `LinkMarkup` adds `url` (1-2048 chars).
- `UserMentionMarkup` adds `user_link` (nullable `@username`) and `user_id` (nullable UserId).
- All other types (`strong`, `emphasized`, `monospaced`, `strikethrough`, `underline`, `heading`, `highlighted`, `quote`) carry no extra fields beyond the base.

Note: the schema's free-text description of the discriminator lists a value named "header", but the actual mapping key and object are `heading`/`HeadingMarkup` — use `heading`, it is what the API sends.
