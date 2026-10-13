> Source: https://dev.max.ru/docs-api + live TLS inspection of the hosts (openssl, 2026-09-21) ·
> verified 2026-09-21. If this looks outdated, re-run `openssl s_client -connect platform-api2.max.ru:443 -showcerts` and re-check the download URLs below.

# TLS trust: `platform-api2.max.ru` and the Минцифры root CA

Base URL and CA trust for every MAX API call, in any language.

## What changed and why it breaks

- Base URL for all Bot API calls: **`https://platform-api2.max.ru`**. The old
  `https://platform-api.max.ru` is deprecated; mandatory cutover was 2026-07-19.
- Certificate chain: leaf `*.max.ru` → **Russian Trusted Sub CA** → **Russian Trusted Root CA**
  (O = Ministry of Digital Development and Communications of the Russian Federation,
  "Минцифры"). The server sends the leaf + Sub CA; your trust store only needs the **root**.
- The old `platform-api.max.ru` chained to HARICA, a globally-trusted CA — that's why code
  written before the cutover "just worked" with no extra setup.
- The Russian Trusted Root CA is **not** in the default trust stores of Mozilla, Go, Node, or
  standard Docker base images — any outbound call to `platform-api2.max.ru` from an unpatched
  environment fails TLS verification.
- The **Sub CA expires 2027-03-06** — do not pin it. Trust the **root** only; the server-sent
  Sub CA keeps working as long as the root is trusted, and MAX is expected to rotate the Sub CA
  before it expires.

## What does NOT need the extra CA

| Host | Used for | CA |
|---|---|---|
| `platform-api2.max.ru` | Bot API (all methods) | Russian Trusted Root — **required** |
| `iu.oneme.ru`, `fu.oneme.ru` | image / file upload | Let's Encrypt — globally trusted |
| `omub.okcdn.ru`, `omu.okcdn.ru` | video / audio upload | HARICA — globally trusted |
| `st.max.ru` | Bridge CDN script (`max-web-app.js`) | HARICA — globally trusted |

Only calls to `platform-api2.max.ru` need the Минцифры root added. Upload traffic and the
Bridge script do not.

## Getting the certificate

- Root: `https://gu-st.ru/content/lending/russian_trusted_root_ca_pem.crt` — CN `Russian Trusted
  Root CA`, expires 2032-02-27, SHA-256 fingerprint
  `D2:6D:2D:02:31:B7:C3:9F:92:CC:73:85:12:BA:54:10:35:19:E4:40:5D:68:B5:BD:70:3E:97:88:CA:8E:CF:31`.
- Sub (do not pin, informational): `https://gu-st.ru/content/lending/russian_trusted_sub_ca_pem.crt`
  — CN `Russian Trusted Sub CA`, expires 2027-03-06.
- Landing page (may be geo/network-restricted): `https://www.gosuslugi.ru/crt`.

Verify the fingerprint before trusting the downloaded file:

```bash
curl -fsSL -o russian_trusted_root_ca.pem \
  https://gu-st.ru/content/lending/russian_trusted_root_ca_pem.crt
openssl x509 -in russian_trusted_root_ca.pem -noout -fingerprint -sha256
# compare to D2:6D:2D:02:31:B7:C3:9F:92:CC:73:85:12:BA:54:10:35:19:E4:40:5D:68:B5:BD:70:3E:97:88:CA:8E:CF:31
```
<!-- nocompile -->

## Go: trust the root via `WithHTTPClient`

The client has no built-in CA option — build an `*http.Client` with the root in its pool and
pass it via `maxbot.WithHTTPClient`:

```go
package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"net/http"
	"os"

	maxbot "github.com/max-messenger/max-bot-api-client-go/v2"
)

func newTrustedApi(token string) (*maxbot.Api, error) {
	pemBytes, err := os.ReadFile(os.Getenv("MAX_ROOT_CA_PATH"))
	if err != nil {
		return nil, fmt.Errorf("read root CA: %w", err)
	}

	pool, err := x509.SystemCertPool()
	if err != nil || pool == nil {
		pool = x509.NewCertPool()
	}
	if ok := pool.AppendCertsFromPEM(pemBytes); !ok {
		return nil, fmt.Errorf("no valid certificates found in %s", os.Getenv("MAX_ROOT_CA_PATH"))
	}

	httpClient := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{RootCAs: pool},
		},
	}

	return maxbot.NewApi(token, maxbot.WithHTTPClient(httpClient))
}

func main() {
	api, err := newTrustedApi(os.Getenv("MAX_BOT_TOKEN"))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	info, err := api.Bots.GetMyInfo(context.Background())
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println(info.UserID)
}
```

`x509.SystemCertPool()` starts from the OS store so other HTTPS calls your bot makes keep
working; `AppendCertsFromPEM` adds the Минцифры root on top — never replace the pool wholesale.
To avoid depending on a file at runtime, embed the PEM instead:

```go
//go:embed russian_trusted_root_ca.pem
var rootCAPEM []byte
```
<!-- nocompile -->

(`//go:embed` requires `import _ "embed"` and the PEM file to sit next to the source file — shown
here as a standalone declaration, not a full program.)

## Node / TS: no CA option in the SDK — two ways to add trust

`@maxhub/max-bot-api` has no `ca`/`agent`/`tls` option (`ClientOptions` only has `baseUrl` and
`fetch`). Fix trust at the process or transport level instead.

**Simplest — process-wide env var** (works for `fetch`, and for most other Node HTTP clients):

```bash
NODE_EXTRA_CA_CERTS=/etc/ssl/certs/russian_trusted_root_ca.pem node bot.js
```
<!-- nocompile -->

**Alternative — inject a custom `fetch`** via `clientOptions.fetch`, backed by an `undici`
`Agent` pinned to the root (useful when you cannot set process env vars, e.g. shared hosting):

```typescript
import { readFileSync } from 'node:fs';
import { Agent, fetch as undiciFetch } from 'undici';
import { Bot, type FetchFn } from '@maxhub/max-bot-api';

const agent = new Agent({
  connect: { ca: readFileSync(process.env.MAX_ROOT_CA_PATH ?? '/etc/ssl/certs/russian_trusted_root_ca.pem') },
});

const trustedFetch = ((input: Parameters<FetchFn>[0], init?: Parameters<FetchFn>[1]) =>
  undiciFetch(input as string, { ...(init as Record<string, unknown>), dispatcher: agent })) as unknown as FetchFn;

const bot = new Bot(process.env.MAX_BOT_TOKEN ?? '', {
  clientOptions: { fetch: trustedFetch },
});

void bot.start();
```

This custom `fetch` only covers Bot API JSON calls (`/me`, `/updates`, `/messages`, the
`/uploads` URL-issuing call). File upload bytes go over a separate raw `node:http`/`https`
transport with no CA hook at all — but that transport talks to the upload hosts in the table
above, none of which need the extra root.

## Docker

Debian/Ubuntu base images (Alpine: add `RUN apk add --no-cache ca-certificates` first):

```dockerfile
COPY russian_trusted_root_ca.pem /usr/local/share/ca-certificates/russian_trusted_root_ca.crt
RUN update-ca-certificates
ENV NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/russian_trusted_root_ca.crt
```
<!-- nocompile -->

`update-ca-certificates` updates the OS store, which Go picks up automatically — but Node's
built-in `fetch`/TLS stack ignores the OS store and needs `NODE_EXTRA_CA_CERTS` set explicitly
regardless (drop that line for Go-only images).

## curl / Python

```bash
curl --cacert /path/russian_trusted_root_ca.pem https://platform-api2.max.ru/me \
  -H "Authorization: $MAX_BOT_TOKEN"
```
<!-- nocompile -->

```python
import os
import requests

resp = requests.get(
    "https://platform-api2.max.ru/me",
    headers={"Authorization": os.environ["MAX_BOT_TOKEN"]},
    verify=os.environ["MAX_ROOT_CA_PATH"],  # path to russian_trusted_root_ca.pem
)
```
<!-- nocompile -->

`SSL_CERT_FILE=/path/russian_trusted_root_ca.pem` works as a process-wide equivalent for
Python's default `ssl`/`requests` trust store, analogous to Node's `NODE_EXTRA_CA_CERTS`.

## Incoming webhooks: the reverse direction

The rules above are for your bot calling *out* to `platform-api2.max.ru`. Your webhook receiver
also needs a valid TLS cert for MAX to call *in* — see `references/webhooks-and-security.md` for
the delivery/port/timeout requirements. A certificate issued by Минцифры **is** an acceptable
cert for that inbound side too (it doesn't have to be a "globally trusted" CA there — MAX accepts
its own Минцифры-issued certs as well as ordinary trusted-CA certs).

## Troubleshooting by exact error string

| Error string | Cause | Fix |
|---|---|---|
| `x509: certificate signed by unknown authority` (Go) | Root CA missing from the pool passed to the HTTP client | Add the root via `WithHTTPClient` as above; confirm the PEM file is valid with `openssl x509 -in ... -noout -text` |
| `unable to get local issuer certificate` / `UNABLE_TO_GET_ISSUER_CERT_LOCALLY` (Node) | Root CA missing from Node's trust store | Set `NODE_EXTRA_CA_CERTS`, or supply a custom `fetch` backed by an `undici.Agent` with `connect.ca` |
| curl exit code `60` (`SSL certificate problem: unable to get local issuer certificate`) | Root CA missing from curl's/system CA bundle | Pass `--cacert /path/russian_trusted_root_ca.pem` |
| `CERTIFICATE_VERIFY_FAILED` (Python) | Root CA missing from Python's `certifi`/system bundle | Pass `verify=<path-to-pem>` to `requests`, or set `SSL_CERT_FILE` |
| `x509: certificate signed by unknown authority` right after `update-ca-certificates` ran | PEM not actually in `/usr/local/share/ca-certificates/`, or Node ignoring the OS store | Recheck the Dockerfile `COPY` path/extension (`.crt`), and set `NODE_EXTRA_CA_CERTS` explicitly for Node — it does not read the OS store the way Go does |

## Never do this

Do **not** work around any of the errors above with `InsecureSkipVerify: true` (Go),
`NODE_TLS_REJECT_UNAUTHORIZED=0` (Node), `verify=False` (Python `requests`), or `curl -k`. Each
of these disables certificate validation entirely — for every host your process talks to, not
just `platform-api2.max.ru` — and defeats TLS. Fix the trust store instead; it is one file copy
or one env var, not a reason to turn off verification, even "temporarily" or "just locally."
