> Source: DOCS https://dev.max.ru/docs-api (methods/POST/subscriptions, "Рекомендации") +
> BRIDGE https://dev.max.ru/docs/webapps/validation + https://dev.max.ru/docs/webapps/bridge +
> GO github.com/max-messenger/max-bot-api-client-go/v2@c832c5b (`v2.4.0`) +
> TS @maxhub/max-bot-api@0.3.1 · verified 2026-09-21. If this looks outdated, re-check those pages
> and the client release notes.

# Webhooks and security

**Contents:** [Subscribing to updates](#subscribing-to-updates) · [Delivery requirements](#delivery-requirements) · [Secret header verification](#secret-header-verification) · [The three HMAC formulas, side by side](#the-three-hmac-formulas-side-by-side) · [Long polling vs. webhook](#long-polling-vs-webhook) · [Pitfalls](#pitfalls)

All MAX verification formulas in one place: the webhook secret header, mini-app
`initData`, and the two phone/contact HMAC hashes, with tested Go and TypeScript code.
For TLS/CA trust of the API host see `references/tls-trust.md`.

## Subscribing to updates

`POST /subscriptions`, body:

| Field | Type | Notes |
|---|---|---|
| `url` | string, required | Must start with `https://`. |
| `update_types` | string[], optional | Which `update_type` values to receive; omit for all. |
| `secret` | string, optional but strongly recommended | 5–256 chars, allowed set `[A-Za-z0-9_-]`. Sent back on every delivery, see below. |

`GET /subscriptions` lists active subscriptions; `DELETE /subscriptions?url=<url>` removes one.
Webhook and long polling are mutually exclusive — subscribing to a webhook URL implicitly stops
long polling working for production traffic (see "Long polling vs. webhook" below).

## Delivery requirements

- Webhook endpoint must listen on **port 443** only — do not put a port number in the `url`.
- TLS: certificate from a trusted CA, **or a Минцифры-issued certificate** (see
  `references/tls-trust.md`); no self-signed certs; the domain in `url` must match the
  certificate's CN/SAN; the server must present the full chain. **Since 2026-05-25**, plain HTTP
  delivery and self-signed certs are rejected outright — this is a hard requirement, not a
  recommendation.
- Your endpoint must answer **HTTP 200 within 30 seconds**. Anything else (wrong status, timeout,
  connection error) counts as a failed delivery.
- Failed deliveries retry up to **10 times** with exponentially increasing intervals: 60s, then
  150s (×2.5), then 375s (×2.5), and so on.
- If no delivery succeeds within **8 hours** of the triggering event, MAX auto-unsubscribes your
  bot from that webhook URL — you stop receiving updates silently until you re-subscribe.

## Secret header verification

MAX sends the `secret` you configured back on every webhook POST as header
**`X-Max-Bot-Api-Secret`**. You must compare it in constant time — a naive `==`/`!=` string
comparison leaks timing information about how many leading bytes matched, which is a real (if
narrow) side channel for guessing a long-lived secret.

**Known gap in the official Go client:** `Api.GetHandler`'s own secret check uses plain Go
`!=`, not `subtle.ConstantTimeCompare` (`bot.go`, `Api.GetHandler`, v2.4.0) — despite
using constant-time comparison correctly elsewhere (`ValidateInitData`, below). If you use
`GetHandler` as shipped, wrap it as shown below to get a constant-time check; do not assume the
SDK already does this for you.

**The TS client gets this right by default:** `bot.start({mode:'webhook',...})`,
`bot.webhookCallback(...)`, and `bot.createWebhook(...)` all compare the header with Node's
`timingSafeEqual` after an equal-length check. One behavioral quirk to know: a mismatched or
missing header returns **404 Not Found**, not 401/403 — don't build alerting that only watches
for 401s. If you leave `secret` unset, the TS SDK accepts **any** request to the webhook path
with no check at all — always set a secret in production.

```go
package main

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"

	maxbot "github.com/max-messenger/max-bot-api-client-go/v2"
	"github.com/max-messenger/max-bot-api-client-go/v2/model"
)

// secureWebhook wraps a handler (e.g. api.GetHandler's own result) with a constant-time
// secret check, closing the gap in GetHandler's own plain `!=` comparison.
func secureWebhook(next http.HandlerFunc, secret string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		got := r.Header.Get("X-Max-Bot-Api-Secret")
		if subtle.ConstantTimeCompare([]byte(got), []byte(secret)) != 1 {
			http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
			return
		}
		next(w, r)
	}
}

// validateInitData implements the mini-app initData algorithm
// (https://dev.max.ru/docs/webapps/validation). Pass window.WebApp.initData exactly as the
// client sent it. It is URL-decoded once here — see the Pitfall about maxbot.ValidateInitData.
func validateInitData(initData, botToken string, maxAge time.Duration) (bool, error) {
	values, err := url.ParseQuery(initData)
	if err != nil {
		return false, fmt.Errorf("parse initData: %w", err)
	}

	hashValues, ok := values["hash"]
	if !ok || len(hashValues) != 1 {
		return false, fmt.Errorf("hash parameter must be present exactly once")
	}
	receivedHash := hashValues[0]
	values.Del("hash")

	authDate, err := strconv.ParseInt(values.Get("auth_date"), 10, 64)
	if err != nil {
		return false, fmt.Errorf("parse auth_date: %w", err)
	}
	if time.Since(time.Unix(authDate, 0)) > maxAge {
		return false, fmt.Errorf("auth_date is stale")
	}

	pairs := make([]string, 0, len(values))
	for key, vals := range values {
		for _, v := range vals {
			pairs = append(pairs, key+"="+v)
		}
	}
	sort.Strings(pairs)
	dataCheckString := strings.Join(pairs, "\n")

	secretMAC := hmac.New(sha256.New, []byte("WebAppData"))
	secretMAC.Write([]byte(botToken))
	secretKey := secretMAC.Sum(nil)

	mac := hmac.New(sha256.New, secretKey)
	mac.Write([]byte(dataCheckString))
	computedHash := hex.EncodeToString(mac.Sum(nil))

	if subtle.ConstantTimeCompare([]byte(receivedHash), []byte(computedHash)) != 1 {
		return false, fmt.Errorf("hash verification failed")
	}
	return true, nil
}

// verifyPhoneHash checks the hash returned by Bridge's requestContact() (a separate, simpler
// formula than initData: no "WebAppData" pre-derivation, raw bot token as the HMAC key).
func verifyPhoneHash(authDate, phone, userID, hash, botToken string) bool {
	phone = strings.TrimPrefix(phone, "+")
	message := strings.Join([]string{
		"authDate=" + authDate,
		"phone=" + phone,
		"userId=" + userID,
	}, "\n")

	mac := hmac.New(sha256.New, []byte(botToken))
	mac.Write([]byte(message))
	computed := hex.EncodeToString(mac.Sum(nil))

	return subtle.ConstantTimeCompare([]byte(computed), []byte(hash)) == 1
}

// verifyContactHash checks the `hash` on a `contact` attachment received via a Bot API
// request_contact button — a THIRD, distinct formula from initData and requestContact.
func verifyContactHash(vcfInfo, hash, botToken string) bool {
	// vcf_info exactly as received; after JSON decoding it already contains real CRLF line breaks.
	mac := hmac.New(sha256.New, []byte(botToken))
	mac.Write([]byte(vcfInfo))
	computed := hex.EncodeToString(mac.Sum(nil))

	return subtle.ConstantTimeCompare([]byte(computed), []byte(hash)) == 1
}

func main() {
	token := os.Getenv("MAX_BOT_TOKEN")
	secret := os.Getenv("MAX_WEBHOOK_SECRET")

	api, err := maxbot.NewApi(token)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	updateHandler := func(_ context.Context, upd model.Update) {
		fmt.Println("received update:", upd.UpdateType)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/webhook", secureWebhook(api.GetHandler(updateHandler, secret), secret))

	mux.HandleFunc("/mini-app/auth", func(w http.ResponseWriter, r *http.Request) {
		// The mini-app POSTs window.WebApp.initData as the raw request body.
		body, err := io.ReadAll(io.LimitReader(r.Body, 8<<10))
		if err != nil {
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}
		if ok, err := validateInitData(string(body), token, time.Hour); !ok {
			http.Error(w, "invalid initData: "+err.Error(), http.StatusUnauthorized)
			return
		}
		w.WriteHeader(http.StatusOK)
	})

	if err := http.ListenAndServe(":8443", mux); err != nil {
		fmt.Fprintln(os.Stderr, err)
	}
}
```

```typescript
import { createHmac, timingSafeEqual } from 'node:crypto';
import type { NextFunction, Request, Response } from 'express';

const SECRET_HEADER = 'x-max-bot-api-secret';

/** Constant-time secret check for a hand-rolled Express webhook route. If you use the SDK's
 * own bot.start({mode:'webhook',...}) / bot.webhookCallback() / bot.createWebhook(), it already
 * does this (and returns 404, not 401, on mismatch) — this is only for raw-HTTP receivers. */
export function verifyWebhookSecret(secret: string) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const got = Buffer.from(String(req.header(SECRET_HEADER) ?? ''), 'utf8');
    const want = Buffer.from(secret, 'utf8');
    if (got.length !== want.length || !timingSafeEqual(got, want)) {
      res.status(404).end();
      return;
    }
    next();
  };
}

/** https://dev.max.ru/docs/webapps/validation two-step HMAC. Pass window.WebApp.initData as
 * sent by the client. Enforces the recommended auth_date freshness window (default 1 hour). */
export function validateInitData(
  initData: string,
  botToken: string,
  maxAgeSeconds = 3600,
): boolean {
  // URLSearchParams decodes each value exactly once and handles both %20 and "+" for spaces.
  const params = new URLSearchParams(initData);

  const hashes = params.getAll('hash');
  if (hashes.length !== 1) return false;
  const receivedHash = hashes[0];
  params.delete('hash');

  const authDate = Number(params.get('auth_date'));
  if (!Number.isFinite(authDate)) return false;
  if (Math.floor(Date.now() / 1000) - authDate > maxAgeSeconds) return false;

  const launchParams = [...params]
    .map(([key, value]) => `${key}=${value}`)
    .sort()
    .join('\n');

  const secretKey = createHmac('sha256', 'WebAppData').update(botToken).digest();
  const computedHash = createHmac('sha256', secretKey).update(launchParams).digest('hex');

  const a = Buffer.from(computedHash, 'hex');
  const b = Buffer.from(receivedHash, 'hex');
  return a.length === b.length && timingSafeEqual(a, b);
}

/** Bridge requestContact() hash — separate, simpler formula than initData: raw bot token as the
 * HMAC key, no "WebAppData" pre-derivation. `phone` must have its leading "+" stripped first. */
export function verifyPhoneHash(
  authDate: string,
  phone: string,
  userId: string,
  hash: string,
  botToken: string,
): boolean {
  const normalizedPhone = phone.startsWith('+') ? phone.slice(1) : phone;
  const message = [`authDate=${authDate}`, `phone=${normalizedPhone}`, `userId=${userId}`].join('\n');
  const computed = createHmac('sha256', botToken).update(message).digest('hex');

  const a = Buffer.from(computed, 'hex');
  const b = Buffer.from(hash, 'hex');
  return a.length === b.length && timingSafeEqual(a, b);
}

/** Bot API request_contact button — a THIRD, distinct formula: HMACs the vcf_info text of the
 * contact attachment with the bot token. Only valid for contacts shared via a request_contact
 * button; contacts forwarded from the address book have no hash to check. */
export function verifyContactHash(vcfInfo: string, hash: string, botToken: string): boolean {
  // vcf_info exactly as received; after JSON.parse it already contains real CRLF line breaks.
  const computed = createHmac('sha256', botToken).update(vcfInfo).digest('hex');

  const a = Buffer.from(computed, 'hex');
  const b = Buffer.from(hash, 'hex');
  return a.length === b.length && timingSafeEqual(a, b);
}
```

## The three HMAC formulas, side by side

It is easy to mix these up — they all HMAC-SHA256 something with something bot-token-shaped, and
two of the three are used together in the same mini-app auth flow.

| Formula | Key | Message | Where it comes from |
|---|---|---|---|
| `initData` (mini-app auth) | `HMAC_SHA256("WebAppData", botToken)` (two-step: this is the *derived* key) | sorted `key=value\n`-joined fields, `hash` excluded | `window.WebApp.initData`, validated on your backend |
| `requestContact()` phone | raw `botToken` | `authDate=<v>\nphone=<v>\nuserId=<v>` (phone without `+`) | Bridge `requestContact()` result |
| `request_contact` button contact | raw `botToken` (Bot API calls this `access_token`, same value) | `vcf_info` exactly as received (JSON-decoded, lines separated by CRLF) — DOCS: `HMAC-SHA256(access_token, vcf_info)` | `contact` attachment on a `message_created` update |

Only `initData` has the extra `"WebAppData"` key-derivation step — the other two HMAC directly
with the bot token. Confusing these two shapes is the single most common mistake when
implementing mini-app/contact verification from scratch; the Go client's own `bot.go` gets the
`initData` one right (constant-time compare) but its plain webhook-secret check above shows even
the official SDK isn't uniformly careful about this class of bug.

## Long polling vs. webhook

- Long polling (`GET /updates`) is **dev/test only** — it is rate/retention-limited and not
  recommended for production traffic.
- Webhook is required for production. You cannot run both at once: subscribing to a webhook URL
  and calling `GET /updates` against the same bot token will fight each other; pick one per
  environment (poll locally during development, webhook in deployed environments).
- The TS SDK enforces this: `bot.start()` in polling mode removes all webhook subscriptions; in
  webhook mode it removes subscriptions for other URLs and keeps its own. Switching a bot from
  webhook back to polling silently drops the registered webhook. See `references/ts-client.md`.

## Pitfalls

- **`maxbot.ValidateInitData` (Go client v2.4.0) URL-decodes twice** (`url.QueryUnescape` on the whole
  string, then `url.ParseQuery`). Valid initData whose values contain an encoded `&`, `=` or `%`
  (for example a user named `Tom&Jerry`) fails verification. Reproduced with v2.4.0. Use the
  standalone `validateInitData` above (single decode) or pre-check your users' data.

| Pitfall | Detail |
|---|---|
| Trusting `initDataUnsafe` | It is explicitly client-side-only convenience data — never treat it as validated; always check the raw `initData` string server-side. |
| Assuming 401 on a bad webhook secret | The TS SDK's built-in webhook handling answers **404**, not 401/403, on a secret mismatch. |
| Reusing the `initData` HMAC shape for phone/contact hashes | Both of those skip the `"WebAppData"` key-derivation step and HMAC directly with the bot token — see the table above. |
| Comparing hashes with `==`/`!=` | Always use a constant-time comparison (`subtle.ConstantTimeCompare` in Go, `timingSafeEqual` after an equal-length check in Node) — string equality leaks timing information. |
| Verifying a forwarded/address-book contact with the `request_contact` hash formula | Only contacts shared via an actual `request_contact` button carry a `hash` at all; there is nothing to verify for other contact-sharing paths. |
