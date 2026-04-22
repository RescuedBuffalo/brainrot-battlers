# Brainrot Autobattler — Design System v0.1

> Foundational system for a TFT-style Roblox autobattler with an Italian-brainrot roster.
> **Aesthetic direction:** chaotic-brainrot characters, readable game UI. The roster is the loud part; the chrome stays tight.

**Owner:** Aidan · **Last updated:** 2026-04-20 · **Status:** Draft for review

---

## 1. Design Principles

1. **Roster screams, chrome whispers.** Characters, emotes, VO, reward moments, and lore can be as unhinged as the meme demands. HUDs, tooltips, shop, and any information-dense surface stay clean and legible.
2. **Sticker outlines everywhere.** A consistent dark outline (UIStroke) around cards, badges, unit portraits, and meaningful chrome. This is our signature and the thing that makes screenshots look like "our game."
3. **Saturate on purpose.** Default to saturated primaries for brand and rarity, never pastels. But leave breathing room — Ink-900 canvas so the colors pop.
4. **One flourish per component.** A button can bounce OR sparkle, not both. A card can have a rarity glow OR an animated border, not both. Stacked effects cheapen the signature moments.
5. **Reward maximalism is earned.** Confetti, screen shake, VO stings, and meme-emoji bursts are reserved for: level ups, legendary+ pulls, streak wins, round wins. Do NOT spray them on hovers or routine clicks.
6. **Readable over clever in copy.** Tooltips, errors, and tutorial text say what they mean. Brainrot tone (“CERTIFIED COOKED,” “SIGMA GRINDSET Lv. 10”) lives in reward moments, match events, and marketing — not inline help.
7. **Cross-device by default.** Game plays on PC, console, mobile, and tablet. Min touch target 44×44, UIScale must support 1.0/1.2/1.4.

---

## 2. Design Tokens

All tokens use a namespaced name (`category.tier.variant`). The canonical source is `tokens.json` (DTCG / Figma Tokens Studio compatible).

### 2.1 Color

**Brand**

| Token | Hex | Use |
|---|---|---|
| `brand.cookedRed` | `#FF3B47` | Primary CTA, logo, defeat stinger |
| `brand.skibidiCyan` | `#00E0FF` | Info, secondary CTA, link |
| `brand.gyattYellow` | `#FFD23A` | Currency, highlight, ability mana |
| `brand.sigmaPurple` | `#A445FF` | Accent, premium/pass, special abilities |
| `brand.brainrotLime` | `#B6FF3C` | Trait icon family A, success ambient |

**Rarity / Tier** — MUST be paired with a shape glyph for colorblind users (see §5 Accessibility).

| Token | Hex | Glyph | Use |
|---|---|---|---|
| `rarity.common` | `#A8AEBF` | ○ circle | Tier 1 units |
| `rarity.uncommon` | `#42D17B` | ◇ diamond | Tier 2 |
| `rarity.rare` | `#3D8BFF` | ▲ triangle | Tier 3 |
| `rarity.epic` | `#B56AFF` | ★ star | Tier 4 |
| `rarity.legendary` | `#FFB84A` | ✧ sparkle | Tier 5 |
| `rarity.mythic` | animated gradient `#FF3B47 → #FFD23A → #00E0FF → #A445FF` | 👑 crown | Chase / Brainrot Prime |

**Semantic**

| Token | Hex | Use |
|---|---|---|
| `semantic.success` | `#42D17B` | Win, completion, positive delta |
| `semantic.warning` | `#FFB84A` | Low HP, last round alert |
| `semantic.danger` | `#FF3B47` | Loss, destructive, eliminated |
| `semantic.info` | `#00E0FF` | Tutorial, neutral callout |

**Neutral (Ink scale)**

| Token | Hex | Typical use |
|---|---|---|
| `ink.900` | `#0B0D14` | Canvas, outline stroke (alpha 80%) |
| `ink.800` | `#151925` | Primary panel |
| `ink.700` | `#1E2333` | Elevated panel, tooltip |
| `ink.600` | `#2A3148` | Row hover, input field |
| `ink.500` | `#3A4156` | Divider, disabled fill |
| `ink.400` | `#5B6279` | Secondary icon |
| `ink.300` | `#8A91A8` | Secondary text |
| `ink.200` | `#B8BED0` | Tertiary text |
| `ink.100` | `#D6DAE6` | Primary text on dark |
| `paper.000` | `#F5F6FA` | Rare light surfaces (toasts on dark) |

**Alpha layer** — use for scrims, veils, and overlays: `overlay.scrim = rgba(11,13,20,0.72)`.

### 2.2 Typography

Roblox supports a fixed font list. We pick four roles from it.

| Role | Roblox `Enum.Font` | CSS fallback | Use |
|---|---|---|---|
| Display | `LuckiestGuy` | `"Luckiest Guy", Impact, sans-serif` | Game title, VICTORY / DEFEAT, level-up burst, marketing |
| Heading | `GothamBlack` | `"Gotham Black", "Montserrat", system-ui` | Screen titles, section headers |
| Body | `GothamMedium` | `"Gotham", "Inter", system-ui` | All body copy, buttons, tooltips |
| Numeric | `RobotoMono` | `"Roboto Mono", ui-monospace` | Timers, gold/HP counters, damage numbers |

**Scale**

| Token | Size / line-height | Font role |
|---|---|---|
| `font.display.xl` | 72 / 78 | Display |
| `font.display.lg` | 48 / 54 | Display |
| `font.h1` | 32 / 38 | Heading |
| `font.h2` | 24 / 30 | Heading |
| `font.h3` | 20 / 26 | Heading |
| `font.body.lg` | 16 / 24 | Body |
| `font.body.md` | 14 / 20 | Body (default) |
| `font.caption` | 12 / 16 | Body |
| `font.micro` | 10 / 14 | Body |
| `font.num.xl` | 48 / 52 | Numeric |
| `font.num.lg` | 24 / 28 | Numeric |
| `font.num.md` | 14 / 18 | Numeric |

**Display type is always UPPERCASE and carries a 2–3px ink.900 UIStroke.** This is the sticker signature.

### 2.3 Spacing (4px grid)

`space.0 = 0`, `space.1 = 4`, `space.2 = 8`, `space.3 = 12`, `space.4 = 16`, `space.5 = 20`, `space.6 = 24`, `space.8 = 32`, `space.10 = 40`, `space.12 = 48`, `space.16 = 64`, `space.20 = 80`.

Component padding defaults: buttons `space.3 × space.5`; cards `space.4`; panels `space.6`; HUD edge inset `space.4` on mobile, `space.6` on desktop.

### 2.4 Radius

| Token | Value | Use |
|---|---|---|
| `radius.none` | 0 | Full-bleed images, progress bars |
| `radius.sm` | 4 | Chips, pills, item badges |
| `radius.md` | 8 | Buttons, tooltips, input fields |
| `radius.lg` | 12 | Cards, shop slots |
| `radius.xl` | 20 | Modals, large panels |
| `radius.full` | 9999 | Avatars, round icon buttons |

### 2.5 Stroke & Elevation

Roblox doesn't do box-shadow natively — we emulate elevation with a combo of UIStroke + background gradient overlays.

| Token | UIStroke | Web shadow equivalent | Use |
|---|---|---|---|
| `stroke.sticker` | `ink.900` @ 80%, 2px | — | Default sticker outline, on every card |
| `stroke.stickerHeavy` | `ink.900` @ 90%, 3px | — | Display type, legendary+ frames |
| `stroke.focus` | `brand.skibidiCyan`, 3px | `0 0 0 3px #00E0FF` | Keyboard focus ring, must be visible on any bg |
| `elev.0` | — | none | Canvas |
| `elev.1` | +1 stroke lighten, tiny gradient | `0 2 4 rgba(0,0,0,0.15)` | Hover lift |
| `elev.2` | — | `0 4 12 rgba(0,0,0,0.25)` | Tooltip, dropdown |
| `elev.3` | — | `0 8 24 rgba(0,0,0,0.35)` | Modal, sheet |
| `elev.4` | — | `0 16 48 rgba(0,0,0,0.45)` | Spotlight / reward |

### 2.6 Motion

| Token | Duration | Easing (Roblox) | CSS easing | Use |
|---|---|---|---|---|
| `motion.fast` | 120ms | `Quart / Out` | `cubic-bezier(0.25, 1, 0.5, 1)` | Hover, small state change |
| `motion.base` | 200ms | `Quart / Out` | same | Default |
| `motion.slow` | 320ms | `Quart / Out` | same | Panel in/out |
| `motion.theatrical` | 500ms | `Back / Out` | `cubic-bezier(0.34, 1.56, 0.64, 1)` | Button press bounce, tier reveal |
| `motion.celebrate` | 900ms | `Elastic / Out` | `cubic-bezier(.68,-0.55,.27,1.55)` | Reward bursts, level-up, chase pulls |

Reduced-motion: replace bounce/elastic with `Quart/Out` at same duration.

---

## 3. Components

Every component below includes: description, variants, states, tokens used, and accessibility. Props listed are "logical" — translate to `Instance` properties in Roblox (`BackgroundColor3`, `TextSize`, `UICorner.CornerRadius`, etc.).

### 3.1 Button

**Description:** Primary interactive affordance.

| Variant | Use |
|---|---|
| `primary` | Main action per screen (BUY, LOCK IN, PLAY) |
| `secondary` | Supporting action (CANCEL, BACK) |
| `ghost` | Inline/low-priority (skip, dismiss) |
| `destructive` | Surrender, leave party, delete |
| `cta-mega` | Big marketing CTAs (PLAY, CLAIM) — display type, oversized |

| Size | Height | Padding | Text |
|---|---|---|---|
| `sm` | 32 | 8×12 | `body.md` |
| `md` (default) | 44 | 12×20 | `body.md` bold |
| `lg` | 56 | 16×24 | `h3` |
| `mega` | 72 | 20×32 | `display.lg` |

| State | Visual |
|---|---|
| default | Filled brand color, `stroke.sticker`, `radius.md` |
| hover | +4% lightness on fill, subtle upward scale (1.02) |
| press | −8% lightness, scale 0.98, 120ms bounce |
| disabled | `ink.500` fill, `ink.300` text, no stroke, no interaction |
| loading | Spinner replaces label, button stays same size |
| focus | `stroke.focus` outside the component (3px cyan ring) |

**Accessibility:** min 44×44; label must describe action; `aria-disabled` when loading; focus ring never hidden.

### 3.2 Icon Button

Square version of Button for HUD utilities (settings, mute, emote wheel). Sizes `sm 32`, `md 44`, `lg 56`. Always has an accessible label (tooltip + screen-reader name).

### 3.3 Unit Card

**Description:** Hover tooltip / collection entry for a brainrot unit. Appears in shop (compact), bench/board tooltip (full), and collection (full).

| Variant | When |
|---|---|
| `compact` | Shop slot, bench, carousel |
| `full` | Hover tooltip, collection detail |

**Anatomy (full):** portrait (1:1) → name → cost badge (top-left) → rarity frame → trait icon row → star tier (under portrait) → ability name + description → stats grid (HP, AD, AP, AR, MR, RNG, AS, Mana).

**Tokens used:** rarity fill for frame + glow; `stroke.sticker` around portrait; `font.h3` for name; `font.body.md` for ability desc; `font.num.md` for stats.

**States:** default / hovered (slight scale 1.03, `elev.2`) / locked (shop, cyan glow pulsing) / purchased-flash (white flash 120ms on buy).

**Accessibility:** name + cost + rarity announced together; trait icons have visible labels on hover AND in reduced-motion/high-contrast mode.

### 3.4 Shop Slot

Row of 5 slots along the bottom-center of the match HUD.

| State | Visual |
|---|---|
| filled | Unit portrait + cost badge + rarity glow |
| empty | Dashed `ink.500` outline, "sold" ghost |
| locked | `brand.skibidiCyan` double-stroke, lock icon bottom-right |
| purchased | 120ms white flash + slot becomes empty |
| refreshed | Slide-up-in from below, 200ms stagger per slot, 40ms between |

### 3.5 Unit Tile (on-board label)

Tight overlay beneath each on-board unit: name (only on hover), tiny HP bar, mana bar, star tier, status-effect chips (stun, burn, shield).

| Prop | Type | Default |
|---|---|---|
| `hp` | 0–1 | 1 |
| `mana` | 0–1 \| null | null |
| `starTier` | 1-3 | 1 |
| `team` | `ally` \| `enemy` | `ally` |
| `statusEffects` | `string[]` | `[]` |

Team color is **shape-distinct, not only color** — ally uses a solid bar, enemy uses a chevron-striped bar. Team color alone never conveys team.

### 3.6 Item Chip

Pill showing one item. `sm` 24h / `md` 32h / `lg` 40h. Icon + optional quantity badge. Tooltip on hover shows item name + effect text.

### 3.7 Trait Badge

Hex-shaped icon + tier color (bronze/silver/gold/chromatic). Left-rail stack during match shows active traits with active-count / threshold (e.g., "3 / 4 Skibidi").

### 3.8 Tooltip

`ink.700` fill, `stroke.sticker`, `radius.md`, `elev.2`, `space.3` padding. Auto-flips when near viewport edge. 120ms fade-in, 60ms fade-out. Max width 320.

### 3.9 Panel / Card

General container. Default: `ink.800` fill, `stroke.sticker`, `radius.lg`, `space.4` padding. Headed variant adds `h3` title + optional action slot top-right.

### 3.10 Modal / Dialog

Centered, max-width 560, `radius.xl`, `elev.3`, `overlay.scrim` behind. Title (`h2`) + body + action row. ESC and backdrop click close non-destructive modals; destructive modals require explicit cancel.

### 3.11 Toast / Banner

Bottom-center toast, `ink.700` fill, lead icon in semantic color, `body.md` text, dismiss on click or 4s auto. Max 3 stacked. Banners (persistent) live at top of screen and use semantic color as a 3px top border.

### 3.12 Progress Bar

| Type | Fill color | Notes |
|---|---|---|
| HP (ally) | `semantic.success` → warning at 40% → danger at 15% | Solid fill |
| HP (enemy) | `semantic.danger` | Chevron-striped pattern for colorblind |
| Mana | `brand.skibidiCyan` | Filled flashes white on full |
| XP | `brand.sigmaPurple` | Small sparkle on level-up |
| Round timer | `brand.gyattYellow` → `semantic.danger` last 5s | Shake last 3s |

### 3.13 Currency Counter

Gold icon + `font.num.lg`. On gain: number counts up over 200ms, small `+N` floater above. On spend: shake 120ms + red flash on number.

### 3.14 Tab Bar

Underline style, active tab `brand.cookedRed` underline 3px, inactive `ink.300`. Keyboard arrows cycle tabs. Always `role="tablist"`.

### 3.15 List Row

Height 56 default, leading avatar/icon + title + meta + trailing action. Hover fills `ink.600`. Selected adds 3px left `brand.cookedRed` bar.

### 3.16 Avatar / Portrait

Circular (`radius.full`), `stroke.sticker`. Variants: `xs 24`, `sm 32`, `md 48`, `lg 64`, `xl 96`. Presence dot bottom-right (green online / grey offline / yellow away / red DND).

### 3.17 Chat Bubble

Rounded `radius.lg` with tail, sender color by team in match / by clan role out of match. Emoji inline at 1.4× line-height. System messages are italic `ink.300`, no bubble.

### 3.18 Reward Burst

**Signature moment component.** Confetti particles (rarity-tinted), center display-type word (“W”, “LEGENDARY”, “LEVEL UP”), 1–3 meme-emoji flyouts, `motion.celebrate` easing. Duration 900ms. Respects reduced-motion: emoji replaced with static badge, no shake.

---

## 4. Screen Patterns

### 4.1 Core Match UI

**Board + HUD layout (landscape, desktop/tablet reference):**

- Top-left: player HP bars (8-player scoreboard, compact)
- Top-center: round timer + phase badge ("Planning / Combat / Carousel")
- Top-right: settings, emote, surrender
- Center: 8×4 hex board (3D game world — UI framed around it)
- Left rail: active traits stack
- Right rail: inventory (items not on units)
- Bottom-center: shop row (5 slots) + XP buy + reroll
- Bottom-left: gold + level + XP bar
- Bottom-right: bench row (9 slots)

**Carousel round:** board darkens with `overlay.scrim`, a circular platform UI highlights the shared carousel, avatars of players orbit. `motion.slow` on avatar arrival.

**Combat phase:** planning controls hide with slide-down exit; damage numbers float up from unit tiles in `font.num.lg` with rarity color if from a high-tier unit; round-end screen overlays VICTORY / DEFEAT display type + gold/HP delta.

### 4.2 Meta / Out-of-Match

- **Main menu:** fullscreen hero with one rotating brainrot character of the week, giant `cta-mega` PLAY button, news strip, battle-pass progress stub, bottom nav (Play / Collection / Pass / Shop / Social).
- **Lobby / matchmaking:** centered modal-style panel, "searching..." with animated trio of brainrot portraits cycling, cancel button, estimated wait.
- **Collection / Dex:** grid of unit cards filtered by cost / trait / owned status. Unowned units show silhouette + "encountered N times" + acquisition method.
- **Battle pass:** horizontal track of tiers, free lane + premium lane, current-tier marker, claimable tier glows, unclaimed reward dots.
- **Cosmetics shop:** featured bundle (hero banner), daily rotation grid of 6, currency pills top-right, preview modal on click.
- **Settings:** tabbed panel (Audio / Graphics / Controls / Accessibility / Account). Accessibility tab is a first-class tab, not buried.

### 4.3 Onboarding / FTUE

- **Welcome screen:** one screen, one CTA. Character greeting (VO + caption) + "Let's go" button.
- **Tutorial overlays:** spotlight cutout on target component, pointer arrow with light bounce, caption card docked to nearest safe edge, "Got it" dismisses. Max 1 overlay at a time.
- **First-match hints:** inline coach marks on first shop, first bench drag, first combat round. Each fires once per account.
- **Reward moment:** full-screen `overlay.scrim` + chest animation + reward burst. Tap to continue.
- **Empty states:** character illustration + 1-line explanation + 1 primary CTA. "No friends yet — add someone from a recent match."

### 4.4 Social / Clan

- **Friends list:** list rows with avatar, presence, current activity ("In match, round 14"), quick-invite action.
- **Party bar:** persistent strip along top when partied (1–4 avatars + leave/ready).
- **Clan hub:** header with clan crest + name + member count, tabs: Members / Chat / Challenges / Settings. Role badges on members.
- **Emote wheel:** radial 8-slot overlay on hold, `motion.fast` in, released emote plays above player avatar.
- **Chat overlay:** bottom-left dockable panel, channels: Global / Party / Clan / Whisper. Collapsible.

---

## 5. Accessibility

- **Contrast:** body text must meet WCAG AA (4.5:1) on every background token pairing. `paper.000` on `brand.cookedRed` fails — never pair them. `ink.900` on `brand.gyattYellow` passes, use it for warnings.
- **Colorblind mode:** rarity shape glyphs (§2.1) become visible at all sizes, not just hover. Enemy HP bars use chevron stripe pattern in addition to red.
- **Reduced motion:** a single Settings toggle replaces bounce/elastic easings with `Quart/Out`, disables screen shake, replaces reward-burst particles with static badge.
- **Text scaling:** UIScale 1.0 / 1.2 / 1.4 options. All containers must accommodate 1.4× without truncation; test the longest expected string.
- **Touch targets:** min 44×44. Shop slots, bench slots, and bench-to-board drag must be comfortable at phone sizes.
- **Subtitles:** all VO has caption track. Captions default ON for first-time users (opt-out, not opt-in).
- **Screen reader / gamepad:** every interactive component has a focusable equivalent. Focus ring (`stroke.focus`) must be visible on every background in the system.

---

## 6. Voice & Copy

**Registers:**

| Register | Where | Example |
|---|---|---|
| Dry-useful | Tooltips, errors, settings | "Not enough gold." "Connection lost. Retrying…" |
| Hype | Match stingers, reward moments, marketing | "CERTIFIED W." "LEGENDARY PULL!" "SIGMA GRINDSET Lv. 10" |
| Charactery | Unit ability names, flavor text, lore | "Bombardiro Crocodilo drops a nuclear mixtape on the lowest-HP enemy." |

**Rules:**

1. Never use hype register in failure or error states. "Skill issue" is not a real error message.
2. Character names stay canonical — don't translate "Tralalero Tralala" into English.
3. Uppercase is reserved for display type, buttons, and stingers. Body copy is sentence case.
4. Numbers in copy get the mono font (`font.num.md`) even inline when they represent game values.

---

## 7. Do's and Don'ts

| ✅ Do | ❌ Don't |
|---|---|
| Pair every rarity color with a shape glyph | Rely on red vs. blue alone for team or rarity |
| Put one flourish per component | Stack bounce + glow + sparkle on the same button |
| Use `LuckiestGuy` only for display/stingers | Use `LuckiestGuy` for body or tooltips |
| Reuse the sticker outline everywhere | Invent a new outline treatment per component |
| Reserve reward-burst for earned moments | Fire reward-burst on hover or routine clicks |
| Test text at UIScale 1.4 before shipping | Truncate with "…" as the default overflow solution |
| Put Accessibility as a first-class Settings tab | Bury motion-reduction inside Advanced |

---

## 8. Roadmap / Priority Actions

Order in which to build this out so the game has a working system fast.

1. **Lock tokens.** Get §2 checked into `tokens.json` and the Roblox equivalent (`ModuleScript` returning a Luau table). Everything else depends on this.
2. **Ship Button + Tooltip + Panel.** These three cover ~60% of surface area. Landing them unlocks almost every screen.
3. **Ship Unit Card (compact) + Shop Slot + Unit Tile.** The match-UI critical path.
4. **Ship Progress Bar + Currency Counter + Trait Badge.** Rest of HUD.
5. **Ship Reward Burst.** Single component, huge perceived-polish win.
6. **Ship Modal + Toast + List Row + Avatar.** Unlocks meta and social screens.
7. **Layer in Reduced Motion + Colorblind mode + UIScale.** Before first public playtest, not after.
8. **Documentation pass.** Every shipped component gets a doc page (use the template in `§3` as the format).

---

## 9. Open Questions

- Do we commit to Luau-based UI (Roblox-native) or Roact/React-Lua for component ergonomics? Affects token binding.
- Is the display font `LuckiestGuy` or do we license a custom font via Roblox's font asset system for brand?
- Mythic rarity animated gradient — runtime expensive on low-end mobile. Acceptable fallback for mobile devices under a perf threshold?
- Do we support gamepad nav from day one or bolt on after soft launch?
- Clan feature scope for v1 vs. post-launch?

---

## 10. Companion Files

- [`design-system-preview.html`](./design-system-preview.html) — open in a browser to see the palette, type scale, and example components rendered live.
- [`tokens.json`](./tokens.json) — DTCG-format design tokens, importable into Figma via the **Tokens Studio** plugin (File → Import → Tokens Studio JSON).
