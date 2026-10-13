> Source: UI github.com/max-messenger/max-ui@1df07bd (npm @maxhub/max-ui 0.5.0) · verified 2026-09-21. dev.max.ru/ui lags the repo (see Migration notes) — if this looks outdated, check the repo first.

# MAX UI — React component library for mini apps

`@maxhub/max-ui` is a Bridge-independent React component library: usable in MAX mini apps, other
super-apps, or standalone web apps. It has **no code dependency on MAX Bridge** (`window.WebApp`)
anywhere in its source — see [Platform and theme detection](#platform-and-theme-detection).

## Install

```shell
npm i @maxhub/max-ui
```

Peer dependencies are **exact pins, not ranges**: `react@19.2.8` and `react-dom@19.2.8`. Trust
`package.json`, not the README — the README's feature list still says "React 18+", which is stale
marketing copy; a strict installer (`npm --strict-peer-deps`, pnpm defaults) can fail against any
other React 19.x patch version until the repo widens this pin.

Import the CSS once, globally (side-effect import — needs a bundler/CSS-loader, not plain `tsc`):

```tsx
import '@maxhub/max-ui/dist/styles.css';
```

The package is ESM-only (`"type": "module"`, no CJS build). No web font is bundled — Android text
styles expect the app to supply the Roboto webfont itself (or rely on the OS having it); iOS uses
the system font stack, no extra font needed.

## Provider: `<MaxUI>`

Wrap the app root once:

```tsx
import type { ReactNode } from 'react';
import { MaxUI } from '@maxhub/max-ui';
import '@maxhub/max-ui/dist/styles.css';

export function Root({ children }: { children: ReactNode }) {
  return (
    <MaxUI platform="ios" colorScheme="dark" resetBody>
      {children}
    </MaxUI>
  );
}
```

| Prop | Type | Default | Notes |
|---|---|---|---|
| `children` | `ReactNode` | — | |
| `platform` | `'ios' \| 'android'` | auto-detected | See detection below. |
| `colorScheme` | `'light' \| 'dark'` | auto-detected | See detection below. |
| `resetBody` | `boolean` | `false` | When `true`, adds a body-reset CSS class to `document.body` on mount, removes it on unmount. |
| `className` | `string` | — | Merged onto the provider's root `<div>`. |

The root `<div>` gets classes `MaxUI`, `MaxUI_colorScheme_<light|dark>`,
`MaxUI_platform_<ios|android>` plus your `className`.

## Platform and theme detection

**Detection is UA/media-query based, not MAX Bridge based** — `max-ui` never reads
`window.WebApp`:

- `platform` default: `navigator.userAgent` regex for `iPad|iPhone|iPod` → `'ios'`; anything else
  (including desktop) → `'android'` (the type only has two values, there is no `'desktop'`/`'web'`
  option here).
- `colorScheme` default: `window.matchMedia('(prefers-color-scheme: dark)')`, and it **stays
  subscribed** to live OS changes unless you pass `colorScheme` explicitly.

If a mini app needs the *real* host platform/theme, read it from Bridge
(`window.WebApp.platform`, see `references/mini-apps-bridge.md`) and pass the result into
`platform`/`colorScheme` explicitly — `max-ui`'s own auto-detection cannot tell a MAX webview from
a plain mobile browser, and it will not lock to the OS theme unless you override it.

Hooks: `usePlatform(): 'ios' | 'android'`, `useColorScheme(): 'light' | 'dark'`,
`useAppearance(): { platform, colorScheme }` (all read from `MaxUIContext`, populated by the
nearest `<MaxUI>`).

## Component catalog

Main exported components (`components/*` + layout from `internal/*`; low-level helpers `Ripple`, `ClearableInput`, `SvgButton`, `Tappable` are also exported but not listed). The
site at `dev.max.ru/ui` **lags this list**: it still shows removed components (`Dot`, `ToolButton`,
`Avatar.OnlineDot`) and a `SearchInput` that doesn't exist in source, and it's missing `Radio`
(added in 0.5.0). Treat the table below, taken from the 0.5.0 source, as authoritative.

| Component | Key props | Notes |
|---|---|---|
| `Avatar.Container` | `size?: 16\|20\|24\|...\|96\|number` (default `40`), `form?: 'circle'\|'squircle'`, `onlineStatus?: boolean`, `overlay?`, `rightTopCorner?`, `rightBottomCorner?: ReactNode` | Online indicator renders only for circular avatars sized 24–80px. |
| `Avatar.Image` | `fallback?: ReactNode`, `fallbackGradient?: AvatarTextGradient` (default `'red'`) | Renders `Avatar.Text` fallback on load error. |
| `Avatar.Text` | `gradient?: 'red'\|'orange'\|'green'\|'blue'\|'purple'\|'custom'` | |
| `Avatar.Icon`, `Avatar.Overlay`, `Avatar.CloseButton` | native `ComponentProps` only | |
| `Button` | `size?: 'xsmall'\|'small'\|'medium'\|'large'`, `variant?: 'primary'\|'secondary'\|'ghost'\|'primary-contrast'\|'secondary-contrast'\|'overlay'\|'destructive'`, `stretched?`, `iconBefore?/iconAfter?/indicator?: ReactNode`, `loading?: boolean` | `loading` disables clicks and shows an internal `Spinner`; Android shows a `Ripple` on tap. |
| `IconButton` | Same `size`/`variant`/`loading` shape as `Button` | |
| `CellAction` | `mode?: 'primary'\|'secondary'\|'themed'\|'destructive'\|'custom'`, `surface?: 'default'\|'island'`, `height?: 'compact'\|'normal'`, `before?: ReactNode`, `showChevron?: boolean` | |
| `CellHeader` | `titleStyle?: 'caps'\|'normal'`, `fullWidth?`, `after?: ReactNode` | |
| `CellInput` | `height?: 'compact'\|'normal'`, `surface?: 'default'\|'island'`, `before?: ReactNode` | |
| `CellList` | `mode?: 'full-width'\|'island'` (default `'full-width'`), `filled?`, `header?: ReactNode` | |
| `CellSimple` | `height?: 'compact'\|'normal'`, `surface?: 'default'\|'island'`, `title?/subtitle?/overline?/before?/after?: ReactNode`, `subtitleMode?: 'secondary'\|'tertiary'`, `showChevron?`, `disabled?`, `separator?`, `link?: string`, `as?: ElementType` | Exports a standalone `Appearance` type not wired to any prop — do not document it as a working prop. |
| `Counter` | `value: number` (required), `variant?: 'primary'\|'primary-contrast'\|'attention'\|'attention-contrast'\|'promo'\|'static'\|'static-contrast'\|'default'\|'mute'\|'menu'`, `rounded?` | |
| `Input` | `mode?: 'default'\|'contrast'`, `size?: 'large'\|'medium'`, `iconBefore?/iconAfter?: ReactNode`, `withClearButton?`, `count?: number`, `hint?: ReactNode` | `size` excludes the native HTML `size` attribute. |
| `Textarea` | `mode?: 'primary'\|'secondary'` | |
| `Radio` | native `<input type="radio">` attrs only | **New in 0.5.0** — not documented on the site yet. |
| `Switch` | native `<input type="checkbox">` attrs only | Renders `role="switch"`; styling varies by platform. |
| `Spinner` | `size?: 20\|24\|number` (default `20`), `appearance?: 'primary'\|'themed'\|'neutral-themed'\|'primary-static'\|'contrast'\|'contrast-static'\|'negative'` | Renders a platform-specific inner spinner via `usePlatform()`. |
| `Typography.Text` | `variant?:` one of `hero/header/subheader/title/body/body-strong/detail/detail-strong/description/description-strong/label/label-strong/tag/tag-strong/note/note-strong/action-large/action-medium/action-small/action-xsmall` (default `'body'`), `color?: 'primary'\|'secondary'\|'tertiary'\|'inherit'` | **Recommended API for new code** (see Migration notes). |
| `Typography.Display/Headline/Title/Body/Label/Action` | each has its own `variant` enum (legacy, still public) | Kept for compatibility; prefer `Typography.Text` for new code even though the README/site quick-start example still uses `Typography.Title`. |
| `Container` | `fullWidth?: boolean` | Layout primitive. |
| `Flex` | `display?: 'flex'\|'inline-flex'`, `direction?: 'row'\|'column'\|'row-reverse'\|'column-reverse'`, `align?`, `justify?: 'start'\|'center'\|'end'\|'space-between'`, `wrap?`, `gap?/gapX?/gapY?: number\|string` | `justify="between"` was renamed to `"space-between"`. |
| `Grid` | `display?: 'grid'\|'inline-grid'`, `align?`, `justify?`, `gap?/gapX?/gapY?`, `cols?/rows?: number` | |
| `Panel` | `mode?: 'primary'\|'secondary'`, `centeredX?/centeredY?: boolean` | Not polymorphic (no `asChild`). |
| `EllipsisText` | `maxLines?: number` (default `1`) | `maxLines > 1` uses `line-clamp` — not supported in all browsers. |

Most interactive components (`Button`, `IconButton`, `CellAction`, `CellSimple`, `Avatar.*`,
`Container`, `Flex`, `Grid`) accept an `asChild` prop (Radix `Slot` pattern) to render as a
different element while keeping the component's styling/behavior.

**Site-documented but absent from `src/**` at this SHA — do not use:** `Dot`, `ToolButton`
(removed 0.3.0, replaced by `Counter`/`Button`/`IconButton`), `Avatar.OnlineDot` (removed, use
`Avatar.Container`'s `onlineStatus` prop), `SearchInput` (absent from source, no removal note
found — treat as gone). A `Profile` composition is documented on the site with no corresponding
`src/compositions/` directory in this repo state — do not document its behavior.

## Hooks and helpers

| Export | Signature | Notes |
|---|---|---|
| `usePlatform()` | `(): 'ios' \| 'android'` | |
| `useColorScheme()` | `(): 'light' \| 'dark'` | |
| `useAppearance()` | `(): { platform, colorScheme }` | |
| `useSystemColorScheme(params?)` | `(params?: { listenChanges?: boolean }): 'light' \| 'dark'` | Reads `prefers-color-scheme`; used internally by `MaxUI`. |
| `useCallbackRef(callback)` | `<T extends (...a: any[]) => any>(callback: T \| undefined): T` | Stable-identity callback ref. |
| `useImageLoadingStatus({ src?, referrerPolicy? })` | `(): 'idle' \| 'loading' \| 'loaded' \| 'error'` | Backs `Avatar.Image`'s fallback logic. |
| `mergeRefs(...refs)`, `hasReactNode(value)`, `getSubtree(props)` | helper functions | Root-level exports for building your own polymorphic components. |
| `Slot`, `SlotProps`, `Slottable` | re-exported from `@radix-ui/react-slot` | Same primitive `asChild` is built on. |

## Example screen

Form with inputs, a switch and a button inside a `Panel`, valid against
`@maxhub/max-ui@0.5.0` + `react@19.2.8`. **Verified compiling under `moduleResolution: "bundler"`
(Vite/webpack/CRA/Next.js default) — see the Pitfalls note right after the code for why `tsc
--moduleResolution nodenext` rejects the same import line.**

```tsx
import { createRoot } from 'react-dom/client';
import { useState } from 'react';
import {
  MaxUI,
  Panel,
  Flex,
  Typography,
  Input,
  Switch,
  Button,
} from '@maxhub/max-ui';
import '@maxhub/max-ui/dist/styles.css';

function SettingsForm() {
  const [name, setName] = useState('');
  const [notifyEnabled, setNotifyEnabled] = useState(true);

  return (
    <Panel mode="secondary" centeredX>
      <Flex direction="column" gap={12}>
        <Typography.Text variant="title">Profile settings</Typography.Text>

        <Input
          placeholder="Display name"
          value={name}
          onChange={(event) => setName(event.target.value)}
          withClearButton
        />

        <Flex align="center" justify="space-between">
          <Typography.Text variant="body">Notifications</Typography.Text>
          <Switch
            checked={notifyEnabled}
            onChange={(event) => setNotifyEnabled(event.target.checked)}
          />
        </Flex>

        <Button stretched disabled={name.length === 0}>
          Save
        </Button>
      </Flex>
    </Panel>
  );
}

const container = document.getElementById('root');
if (container) {
  createRoot(container).render(
    <MaxUI>
      <SettingsForm />
    </MaxUI>,
  );
}

export default SettingsForm;
```

## Pitfalls

- **`moduleResolution: "nodenext"`/`"node16"` breaks named imports from `@maxhub/max-ui@0.5.0`.**
  Verified directly: `import { MaxUI, Panel, Button } from '@maxhub/max-ui'` fails to type-check
  under `tsc --moduleResolution nodenext` with `error TS2305: Module '"@maxhub/max-ui"' has no
  exported member 'MaxUI'` (and likewise for every other component). Root cause: the package's
  `dist/` ships one bundled runtime file (`dist/index.js`) but a full per-component `.d.ts` tree
  with extensionless relative re-exports (`export * from './Avatar'` etc.) and no matching `.js`
  sibling at each of those paths — which strict Node ESM module resolution requires. The identical
  import compiles cleanly under `moduleResolution: "bundler"`, which is the default (or effective
  behavior) for Vite, webpack, Create React App and Next.js — i.e. this only bites projects that
  explicitly set `moduleResolution` to `node16`/`nodenext` (typically Node-only ESM libraries, not
  typical mini-app frontends). If you hit this, switch to `"bundler"` rather than reporting it as a
  bug in your own code.
- CSS is imported as a side-effect (`import '@maxhub/max-ui/dist/styles.css'`) — this requires
  your bundler's CSS loader; plain `tsc` has no ambient type for `*.css` and will reject it unless
  your project supplies one (e.g. Vite's `vite/client` types).

