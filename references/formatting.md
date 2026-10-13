> Source: DOCS https://dev.max.ru/docs-api + SCHEMA github.com/max-messenger/api-schema@1a4a502 · verified 2026-09-21. If anything here looks outdated, check those first.

# Formatting reference

Set text formatting via `NewMessageBody.format` (also `NewCommentBody.format`): `"markdown"` or `"html"`. Omit for plain text. Applies to message/comment `text` only, not button labels or chat titles.

## Markdown ("Max flavored Markdown", based on CommonMark 0.29)

| Effect | Syntax |
|---|---|
| Italic | `*emphasized*` or `_emphasized_` |
| Bold | `**strong**` or `__strong__` |
| Strikethrough | `~~strikethrough~~` |
| Underline | `++underline++` |
| Monospace (inline) | `` `code` `` |
| Monospace (block) | ` ```code``` ` — line breaks inside are collapsed to spaces, not preserved |
| Highlighted (red by default) | `^^highlighted^^` |
| Quote | `> quote` |
| Header | `# Header` (levels `#` to `######`) |
| Inline URL | `[Inline URL](https://dev.max.ru/)` |
| User mention | `[Имя Фамилия](max://user/user_id)` |

Mention rule: put the user's full display name (first + last name from their MAX profile) as the link text, not a placeholder like "User mention". If the user has no last name, use first name only.

```bash
curl -X POST "https://platform-api2.max.ru/messages?chat_id=$CHAT_ID" \
  -H "Authorization: $MAX_BOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text": "Hello, [Ivan Petrov](max://user/123456)!", "format": "markdown"}'
```

## HTML

Only these tags render; anything else is stripped:

| Effect | Tag |
|---|---|
| Italic | `<i>` or `<em>` |
| Bold | `<b>` or `<strong>` |
| Strikethrough | `<del>` or `<s>` |
| Underline | `<ins>` or `<u>` |
| Monospace | `<pre>` or `<code>` |
| Link | `<a href="...">text</a>` |
| Highlighted | `<mark>` |
| Quote | `<blockquote>` |
| Header | `<h1>` … `<h6>` — all levels render identically (no visual size/weight difference) |
| User mention | `<a href="max://user/user_id">Имя Фамилия</a>` |

Same mention rule as markdown: link text is the user's full profile name, first name only if no last name.

```json
{
  "text": "<b>Order confirmed</b>. Contact <a href=\"max://user/123456\">Ivan Petrov</a>.",
  "format": "html"
}
```

## What's not supported

- Lists (ordered/unordered), horizontal rules, and tables have no markdown/HTML syntax in either format — not in the schema's tag/syntax tables. Inferred from absence, not an explicit "unsupported" statement in DOCS.
- Inline images via markdown/HTML text markup — attach media via `attachments`, not the `text` field.
- Nested/mixed nesting beyond a single level per span is undocumented — do not assume CommonMark's full nesting rules apply beyond the elements listed above.
- Monospace blocks do work with triple backticks, but line breaks inside are converted to spaces — treat as degraded, not absent.

## Comments (`NewCommentBody.text`) — restricted subset

Comment text does **not** support hyperlinks or user mentions in either Markdown or HTML, regardless of `format`. This is a DOCS-only restriction (no separate schema field encodes it — `NewCommentBody` just omits `attachments`). All other markdown/HTML elements above (bold, italic, strikethrough, underline, monospace, highlight, quote, headers) work the same as in messages.

## Client version requirements

- Text formatting (markdown/HTML rendering) requires **iOS ≥3.1** and **Android ≥2.20.0**. Older clients show the raw markup/tags unrendered.
- Deep linking (`max://user/...` mentions rely on the same deep-link mechanism) requires **iOS ≥2.7.0** and **Android ≥2.9.0**.

## Practical guidance for editors

- Pick one format per message/comment — mixing markdown syntax into an `html`-formatted string (or vice versa) is not parsed; it renders as literal text.
- Neutralize user-generated content before interpolating it into formatted `text`: a literal `*`, `_`, `` ` ``, `<`, `>` from user input can be parsed as markup. The docs define no escape syntax — strip or replace those characters, or send user content in a separate message without `format`.
- `Message.body.markup` (the parsed, response-side representation) uses `MarkupElement` objects discriminated by `type`. Values: `strong`, `emphasized`, `monospaced`, `strikethrough`, `underline`, `highlighted`, `quote`, `link`, `user_mention`, `heading`. Each has `from` (zero-based start index) and `length`.
  - Note: the schema's own free-text description of `MarkupElement.type` calls this value "header", but the actual discriminator mapping key is `heading` (`HeadingMarkup`). Use `heading` — it is what the API actually sends.
  - `LinkMarkup` adds `url` (1-2048 chars). `UserMentionMarkup` adds `user_link` (nullable `@username`) and `user_id` (nullable) — a mention is resolved by username OR by user_id when the user has none.
- Message/comment `text` is capped at 4000 characters total (see `bot-api.md` limits table) — formatting markup characters count toward this limit.
