> Source: BRIDGE https://dev.max.ru/docs/webapps/bridge · verified 2026-09-21. If this looks outdated, check it first.

# MAX Bridge — Mini Apps SDK reference

**Contents:** [Setup](#setup) · [Top-level properties](#top-level-properties) · [Top-level methods](#top-level-methods) · [Sub-objects](#sub-objects) · [Error shape](#error-shape) · [initData / initDataUnsafe](#initdata--initdataunsafe) · [Validating initData](#validating-initdata) · [requestContact phone verification](#requestcontact-phone-verification) · [Mini-app setup and registration](#mini-app-setup-and-registration) · [Deep links](#deep-links) · [What does not exist](#what-does-not-exist) · [TypeScript ambient declaration](#typescript-ambient-declaration)

Mini apps are static web apps (HTML/JS/CSS) that run only inside a MAX chat-bot — they cannot
exist standalone. `window.WebApp` is the bridge between the page and the MAX client.

## Setup

Load the SDK from CDN, once, before using `window.WebApp`:

```html
<script src="https://st.max.ru/js/max-web-app.js"></script>
```

`window.WebApp` is created automatically on every launch and preloads its data — there is no
separate `init()`/`ready()` call. Every property/method below is available as soon as the script
has loaded.

## Top-level properties

| Property | Type | Notes |
|---|---|---|
| `initData` | `string` | Raw, URL-encoded, UTF-8. The only value safe to use for server-side validation — see [Validating `initData`](#validating-initdata). |
| `initDataUnsafe` | `InitData` | Parsed convenience object built client-side from `initData`. **Never use for validation/auth** — see shape below. |
| `platform` | `'ios' \| 'android' \| 'desktop' \| 'web'` | Platform the mini app was launched from. |
| `version` | `string` | MAX client app version, format `<year>.<build_number>.<patch_version>`, e.g. `25.9.16`. Not the same as a "Bridge SDK version" — no such separate version is documented. Does not participate in any validation hash. |
| `deviceName` | `string` | Human-readable device/client string, e.g. `iPhone 16, iOS 26.5`, `Chrome, macOS`. |

## Top-level methods

All methods that return `Promise` reject with `{ error: { code: string } }` on failure — see
[Error shape](#error-shape).

| Method | Params | Returns | Platform | Gesture / limits |
|---|---|---|---|---|
| `getLaunchContext()` | — | `Promise<{ entryPoint: 'tabbar' \| 'default' }>` | Android ≥26.19.2, iOS ≥26.20.0 | `tabbar` = launched from tab bar; `default` = from a chat, chat list or settings screen. |
| `requestScreenMaxBrightness()` | — | `Promise<{ maxBrightness: boolean }>` | all | Max brightness is held 30s, then auto-restored. |
| `restoreScreenBrightness()` | — | `Promise<{ maxBrightness: boolean }>` | all | Restores the original brightness immediately. |
| `getViewportSize()` | — | `Promise<{ height: string; width: string }>` | all | No fixed/declared viewport constant exists — always read this and adapt layout dynamically. |
| `requestContact()` | — | `Promise<{ phone: string; authDate: string; hash: string }>` | all | Opens a native modal. Data is usable only within the requesting mini app. See [`requestContact` phone verification](#requestcontact-phone-verification). Rejects with `client.request_phone.user_refused_provide_phone_number` or `client.request_phone.request_error`. |
| `enableClosingConfirmation()` | — | — (one-way, fire-and-forget) | all | Enables an "unsaved data" warning when the user tries to close the mini app. |
| `disableClosingConfirmation()` | — | — | all | Disables that warning. |
| `openLink(url)` | `url: string` | — | all | Opens `url` in the external browser. **Requires an immediately-preceding user click/gesture** — Bridge checks for one and silently no-ops without it. |
| `openMaxLink(url)` | `url: string` | — | all | Opens a `https://max.ru/...` deep link inside MAX in a new sheet. Non-matching URLs fall back to the external browser. |
| `downloadFile(url, file_name)` | `url: string` (any HTTPS host), `file_name: string` | Promise, rejects on error | Mini app runtime only — does **not** work when opened in a plain browser tab | Requires an HTTPS `url` (`http://` is rejected) and a **prior user click**. `<a download>`/href downloads are not supported — use only this method. Rejects with `client.download_file.invalid_params` or `client.download_file.request_timeout` (60s native-client timeout). |
| `shareContent(params)` | `{ text?: string; link?: string }` (≥1 required) | — | **Not supported on web** (iOS/Android only) | Opens the native OS share sheet. |
| `shareMaxContent(params)` | `{ text?: string; link?: string }` \| `{ mid: string; chatType: 'DIALOG' \| 'CHAT' }` | — | all | **Requires a prior user click.** Opens the in-MAX share screen. Two modes: text/link sharing, or forwarding a bot-sent message (`mid` = message id returned by `POST /messages`; `chatType` = `DIALOG` for 1:1, `CHAT` for a group the user is a member of). If both shapes are passed together, `text`/`link` are ignored. |
| `openCodeReader(fileSelect?)` | `fileSelect?: boolean` (default `true`) | `Promise<string>` (decoded QR content) | all | `fileSelect=true` also offers the gallery/file picker; `fileSelect=false` is camera-only. |

## Sub-objects

### BackButton

| Member | Signature | Notes |
|---|---|---|
| `isVisible` | `boolean` | Default `false`. |
| `show()` | `(): void` | Makes the header Back button visible/active. |
| `hide()` | `(): void` | Hides it. |
| `onClick(callback)` | `(callback: () => void): void` | Keep a reference to `callback` so you can unsubscribe later. |
| `offClick(callback)` | `(callback: () => void): void` | Removes the handler. |

`BackButton.onClick`/`offClick` is the **only** subscribe/unsubscribe pair documented anywhere on
the Bridge page — see [What does not exist](#what-does-not-exist).

### DeviceStorage

Per-user local device storage tied to the mini app. **Not supported on web.**

| Member | Signature |
|---|---|
| `setItem(key, value)` | `(key: string, value: string): Promise<void>` |
| `getItem(key)` | `(key: string): Promise<string>` |
| `removeItem(key)` | `(key: string): Promise<void>` |
| `clear()` | `(): Promise<void>` — clears all keys the bot previously stored. |

### SecureStorage

Same shape as `DeviceStorage`, encrypted, suited for tokens/secrets/auth state. **Not supported on
web. Hard cap: 10 keys per bot per user** — design your storage schema (namespacing/reuse)
accordingly, this is not unlimited key-value storage.

| Member | Signature |
|---|---|
| `setItem(key, value)` | `(key: string, value: string): Promise<void>` |
| `getItem(key)` | `(key: string): Promise<string>` |
| `removeItem(key)` | `(key: string): Promise<void>` |
| `clear()` | `(): Promise<void>` |

### BiometricManager

**Not supported on desktop or web.** Call `init()` once before any other member.

| Member | Signature | Notes |
|---|---|---|
| `init()` | `(): Promise<BiometryInfo>` | Checks device capability and whether access is granted. |
| `isInited` | `boolean` | Whether `init()` has run. |
| `isBiometricAvailable` | `boolean` | `false` if the user refused access. |
| `isAccessRequested` | `boolean` | `false` if the user refused. |
| `isAccessGranted` | `boolean` | `false` if the user refused. |
| `isBiometricTokenSaved` | `boolean` | Whether an auth token already exists in secure storage. |
| `biometricType` | `Array<'finger' \| 'face' \| 'unknown'>` | `["unknown"]` if refused; Android is always `["unknown"]`. |
| `deviceId` | `string \| null` | `null` if access refused; use to bind a token to this device. |
| `requestAccess(reason?)` | `(reason?: string): Promise<BiometryInfo>` | `reason` is 1–128 chars, truncated beyond that. |
| `authenticate(reason?)` | `(reason?: string): Promise<void>` | Runs the biometric auth flow; the resolved payload beyond success/failure is not documented — don't rely on a specific shape. |
| `updateBiometricToken(token?, reason?)` | `(token?: string, reason?: string): Promise<void>` | Call without `token` to delete the stored one. |
| `openSettings()` | `(): Promise<{ status: 'opened' }>` | Opens native MAX privacy settings. **Closes the mini app.** |

`BiometryInfo` = `{ isInited, isBiometricAvailable, isAccessRequested, isAccessGranted,
isBiometricTokenSaved, biometricType, deviceId }` (same fields as the properties above).

### HapticFeedback

**Not supported on desktop or web.**

| Member | Signature | Notes |
|---|---|---|
| `impactOccurred(impactStyle, disableVibrationFallback?)` | `(impactStyle: 'soft'\|'light'\|'medium'\|'heavy'\|'rigid', disableVibrationFallback?: boolean): void` | For tap/interaction feedback. `disableVibrationFallback` defaults to `false`. |
| `notificationOccurred(notificationType, disableVibrationFallback?)` | `(notificationType: 'error'\|'success'\|'warning', disableVibrationFallback?: boolean): void` | |
| `selectionChanged(disableVibrationFallback?)` | `(disableVibrationFallback?: boolean): void` | Use only when the user's selection *changes*, not when confirming a choice. |

### NfcManager

**Android only.** Call `init()` before any other member.

| Member | Signature | Notes |
|---|---|---|
| `init()` | `(): Promise<{ available: boolean; enabled: boolean; accessRevoked?: boolean }>` | |
| `isInited` | `boolean` | |
| `openSystemSettings()` | `(): Promise<{ status: 'opened' }>` | Opens system NFC settings. **Closes the mini app.** No-op if the user never disabled NFC. |
| `emulateNfcTag(nfctag?)` | `(nfctag?: string): void` | Broadcasts data via NFC; calling with no tag stops broadcasting. |

### ScreenCapture

| Member | Signature |
|---|---|
| `enableScreenCapture()` | `(): Promise<{ isScreenCaptureEnabled: boolean }>` — allows screenshots/screen recording |
| `disableScreenCapture()` | `(): Promise<{ isScreenCaptureEnabled: boolean }>` — disallows them |

## Error shape

Bridge Promise rejections share one generic shape:

```
{ error: { code: string } }
```

Documented codes: `client.download_file.invalid_params`, `client.download_file.request_timeout`,
`client.request_phone.user_refused_provide_phone_number`, `client.request_phone.request_error`.
No other codes are documented — don't invent codes for other methods.

## `initData` / `initDataUnsafe`

```typescript
interface InitData {
  query_id: string;
  ip?: string;
  auth_date: number;
  hash: string;
  user: {
    id: number;
    first_name: string;
    last_name: string;
    username: string;
    language_code: string;
    photo_url: string;
  };
  chat: {
    id: number;
    type: 'DIALOG' | 'CHAT' | 'CHANNEL';
  };
  start_param: string;
}
```

`query_id` — unique session id. `ip?` — user IP. `auth_date` — issuance time, Unix seconds
(recommended validity window: 1 hour). `hash` — signature for validation. `user.*` — profile of
the user opening the mini app. `chat.id`/`chat.type` — chat the mini app was opened in.
`start_param` — the value passed via `?startapp=` on the deep link that opened the mini app (see
[Deep links](#deep-links)).

`initDataUnsafe` is this same object, parsed client-side for convenience — it is **not**
signed/verified data as far as your code is concerned and must never be trusted for
authentication.

## Validating `initData`

`initData` is signed with `HMAC-SHA256`, keyed by the literal string `"WebAppData"` over the bot
token, then that derived key signs the sorted, `\n`-joined `key=value` pairs. The full algorithm
with tested Go and TypeScript validators is in `references/webhooks-and-security.md`.

## `requestContact` phone verification

`requestContact()`'s `hash` is a **different, simpler** formula than `initData`'s: it HMACs the
sorted `authDate`/`phone`/`userId` fields directly with the raw bot token (no `"WebAppData"`
pre-derivation step), and `phone` must have its leading `+` stripped before hashing. Full formula
and code: `references/webhooks-and-security.md`.

## Mini-app setup and registration

Mini apps are registered per-bot on `business.max.ru/self`: **Chat-bots → pick bot → ⋮ →
Settings → paste the mini-app URL → pick a button label (Open / Start / Play / no label) →
Save.** There is no separate mini-app registration outside a bot.

URL requirements: max 1024 chars, protocol **must be `https://`**, allowed characters are Latin
letters, digits, `.` and `-` (no spaces), and it must be a valid URL. The app itself is static
HTML/JS/CSS + assets served over HTTPS from any host (GitHub Pages, Yandex Cloud, VK Cloud, etc.).
Redeploying to the same URL updates the mini app in place; changing the URL requires the bot owner
to update it again in the bot settings. Only one mini app can be open at a time — opening a new
one closes the current one.

To open a mini app from a bot keyboard, use an `open_app` button. The TS client's helper is
`openApp(text, webApp, contactId?, payload?)`. The Go client's `KeyboardRow.AddOpenApp(text,
botID)` sets the button's `web_app` JSON field to the button's display `text`, not a URL — its own
source comment flags this field as `// ignored, required`. Treat Go's `open_app` builder as
suspect; verify the exact field against the API schema (see `references/bot-api.md`) before relying
on it, or build the button JSON by hand if in doubt.

## Deep links

Two distinct formats, not to be confused:

| Link | Payload param | Max length | Scope |
|---|---|---|---|
| `https://max.ru/<botName>?start=<payload>` | `start` | 128 chars | Opens the bot chat only (not mini apps). |
| `https://max.ru/<botName>?startapp=<payload>` | `startapp` | 512 chars | Launches the bot's mini app with `payload` exposed as `start_param`. |

`startapp` payload allowed characters: `A-Za-z0-9_-` only. If the payload exceeds 512 chars or
uses disallowed characters, it is **silently stripped from the URL** — no error is surfaced to the
developer, so validate payload format before constructing links. Both link types require MAX
client iOS ≥2.7.0, Android ≥2.9.0.

The payload reaches the mini app both as `initDataUnsafe.start_param` and inside the raw
`initData` string.

A separate content-share deep link exists: `https://max.ru/:share?text=<message text>` opens a
"send to MAX" chat picker with `text` pre-filled (URL-encode it). Available on iOS, Android, web;
desktop support is "in development" as of this doc's verification date — don't assume parity
across all four `platform` values for this or any other feature without checking its own
platform-restriction note above.

## What does not exist

- **No theme/CSS-variables API.** No `themeParams`, no `--*-theme-*` CSS custom properties, no
  color-scheme signal of any kind is exposed by Bridge. Do not port Telegram-style theming
  assumptions. If a mini app needs to visually match the MAX client, that comes from MAX UI
  components/guidelines (`references/max-ui.md`), not from Bridge.
- **No generic event bus.** There is no `onEvent`/`offEvent`/pub-sub API. The only
  subscribe/unsubscribe pair documented anywhere on this page is `BackButton.onClick`/`offClick`.

## TypeScript ambient declaration

Minimal ambient types for everything documented above — copy into a `.d.ts` file (or the top of a
module) to get editor/compiler support for `window.WebApp`.

```typescript
export {};

declare global {
  interface MaxWebAppInitDataUser {
    id: number; first_name: string; last_name: string;
    username: string; language_code: string; photo_url: string;
  }
  interface MaxWebAppInitDataChat { id: number; type: 'DIALOG' | 'CHAT' | 'CHANNEL'; }
  interface MaxWebAppInitData {
    query_id: string; ip?: string; auth_date: number; hash: string;
    user: MaxWebAppInitDataUser; chat: MaxWebAppInitDataChat; start_param: string;
  }

  interface MaxWebAppBiometryInfo {
    isInited: boolean; isBiometricAvailable: boolean; isAccessRequested: boolean;
    isAccessGranted: boolean; isBiometricTokenSaved: boolean;
    biometricType: Array<'finger' | 'face' | 'unknown'>; deviceId: string | null;
  }

  interface MaxWebAppBackButton {
    readonly isVisible: boolean;
    show(): void;
    hide(): void;
    onClick(callback: () => void): void;
    offClick(callback: () => void): void;
  }

  interface MaxWebAppKeyValueStorage {
    setItem(key: string, value: string): Promise<void>;
    getItem(key: string): Promise<string>;
    removeItem(key: string): Promise<void>;
    clear(): Promise<void>;
  }

  interface MaxWebAppBiometricManager extends MaxWebAppBiometryInfo {
    init(): Promise<MaxWebAppBiometryInfo>;
    requestAccess(reason?: string): Promise<MaxWebAppBiometryInfo>;
    authenticate(reason?: string): Promise<void>;
    updateBiometricToken(token?: string, reason?: string): Promise<void>;
    openSettings(): Promise<{ status: 'opened' }>;
  }

  interface MaxWebAppHapticFeedback {
    impactOccurred(impactStyle: 'soft' | 'light' | 'medium' | 'heavy' | 'rigid', disableVibrationFallback?: boolean): void;
    notificationOccurred(notificationType: 'error' | 'success' | 'warning', disableVibrationFallback?: boolean): void;
    selectionChanged(disableVibrationFallback?: boolean): void;
  }

  interface MaxWebAppNfcManager {
    readonly isInited: boolean;
    init(): Promise<{ available: boolean; enabled: boolean; accessRevoked?: boolean }>;
    openSystemSettings(): Promise<{ status: 'opened' }>;
    emulateNfcTag(nfctag?: string): void;
  }

  interface MaxWebAppScreenCapture {
    enableScreenCapture(): Promise<{ isScreenCaptureEnabled: boolean }>;
    disableScreenCapture(): Promise<{ isScreenCaptureEnabled: boolean }>;
  }

  interface MaxWebAppShareContentParams { text?: string; link?: string; }
  type MaxWebAppShareMaxContentParams =
    | MaxWebAppShareContentParams
    | { mid: string; chatType: 'DIALOG' | 'CHAT' };
  interface MaxWebAppRequestContactResult { phone: string; authDate: string; hash: string; }

  interface MaxWebApp {
    readonly initData: string;
    readonly initDataUnsafe: MaxWebAppInitData;
    readonly platform: 'ios' | 'android' | 'desktop' | 'web';
    readonly version: string;
    readonly deviceName: string;

    readonly BackButton: MaxWebAppBackButton;
    readonly DeviceStorage: MaxWebAppKeyValueStorage;
    readonly SecureStorage: MaxWebAppKeyValueStorage;
    readonly BiometricManager: MaxWebAppBiometricManager;
    readonly HapticFeedback: MaxWebAppHapticFeedback;
    readonly NfcManager: MaxWebAppNfcManager;
    readonly ScreenCapture: MaxWebAppScreenCapture;

    getLaunchContext(): Promise<{ entryPoint: 'tabbar' | 'default' }>;
    requestScreenMaxBrightness(): Promise<{ maxBrightness: boolean }>;
    restoreScreenBrightness(): Promise<{ maxBrightness: boolean }>;
    getViewportSize(): Promise<{ height: string; width: string }>;
    requestContact(): Promise<MaxWebAppRequestContactResult>;
    enableClosingConfirmation(): void;
    disableClosingConfirmation(): void;
    openLink(url: string): void;
    openMaxLink(url: string): void;
    downloadFile(url: string, file_name: string): Promise<void>;
    shareContent(params: MaxWebAppShareContentParams): Promise<void>;
    shareMaxContent(params: MaxWebAppShareMaxContentParams): Promise<void>;
    openCodeReader(fileSelect?: boolean): Promise<string>;
  }

  interface Window { WebApp: MaxWebApp; }
}
```
