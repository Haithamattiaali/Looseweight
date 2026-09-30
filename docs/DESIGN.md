# Looseweight — Design Direction ("The Plate")

## 0. Purpose and the one idea

**Purpose.** This exists so that a person trying to lose weight can know what a meal costs them in the three seconds between sitting down and taking the first bite.

**The single idea:** *The day is a plate — one luminous disc that fills as you eat, and every screen is that same disc seen from a different distance.*

Onboarding draws the plate. Today shows it full-width. Scan lays the live camera inside it. Analyzing lets it "read" the food. Review breaks it into slices. Progress stacks yesterday's plates into a timeline. One object, one morph (`glassEffectID` / `matchedGeometryEffect`), never a new metaphor per screen.

### Removed from today's UI (removal log)
| Removed | Why |
|---|---|
| `GlassCard` wrapping everything | Glass on every surface means glass means nothing. Glass is now **control only** (buttons, pills, sheets, the scan orb). Content sits on the ground. |
| Drifting 3×3 mint/teal mesh behind every screen | Decorative motion competing with food photos. Replaced by a still "Daylight" ground that shifts only with time of day and plate fullness. |
| The 170pt ring + stat column (Eaten / Target / Burn) | Three numbers saying one thing. One number remains: kcal left. Eaten/target move into the plate's rim label. |
| Three separate macro progress bars | Macros become three arcs *inside* the plate's rim — same data, zero extra rows. |
| `SectionTitle` with icons ("Meals") | The timeline structure explains itself. |
| LiDAR `Badge` on every meal row | Care in the unseen: a hairline 3D glyph on the thumbnail corner only. |
| Tab bar with 3 labeled tabs as the primary chrome | Kept for UI tests and familiarity, but minimized on scroll; the scan orb is the hero. |
| Good idea said no to: animated food-emoji confetti on save | Joy lives in the plate filling, not in noise. |

---

## 1. Design tokens (`App/Design/Theme.swift` rewrite)

### 1.1 Palette
One accent, one job: **Leaf** marks "room left / go". **Ember** marks "over". Everything else is neutral + the food's own colour.

| Token | Light | Dark | Use |
|---|---|---|---|
| `ground` | #F6F4EF (warm paper) | #0B0C0B | Screen background |
| `groundRaised` | #FFFFFF | #151715 | Non-glass content rows (rare) |
| `ink` | #111311 | #F3F2EE | Primary text, hero numbers |
| `inkSecondary` | ink @ 60% | ink @ 62% | Labels |
| `inkTertiary` | ink @ 36% | ink @ 40% | Units, captions |
| `hairline` | ink @ 8% | ink @ 12% | Rim track, dividers (0.5pt) |
| `leaf` (accent) | #1F9D6B | #3CCB8C | Remaining kcal fill, shutter-ready, save |
| `ember` | #E4572E | #FF7A52 | Over target, low confidence |
| `honey` | #E9A23B | #F4B654 | Medium confidence, carbs arc |
| `protein` | #D9486A | #F0708D | Protein arc |
| `carbs` | = honey | = honey | Carbs arc |
| `fat` | #4C7BE0 | #7FA3F5 | Fat arc |

Daylight ground: a `MeshGradient(width: 2, height: 2)` whose 4 colours are `ground` blended ≤6% with a time tint (dawn #FFE9C9, noon clear, dusk #F5D6C8, night #1A2233 dark only). Updated once per scene activation, **not animated per frame**. Contrast: ink on ground ≥ 15:1; leaf text on ground ≥ 4.6:1 (use leaf for glyphs/fills, ink for text on it).

### 1.2 Type
Numbers are the product. They get SF Pro **Rounded** (friendly, food) at display sizes; words get SF Pro **Text**; one **Expanded** voice for tiny all-caps labels.

| Token | Font | Size / weight / tracking | Use |
|---|---|---|---|
| `hero` | `.system(size: 88, weight: .semibold, design: .rounded)` + `.monospacedDigit()` | tracking −2 | kcal left on Today, total on Review |
| `display` | rounded 56 semibold | −1 | Plan target, weight |
| `title` | `.system(.title2, weight: .semibold)` (Pro Display auto) | default | Screen titles (inline, not large-title) |
| `headline` | `.system(.headline)` | | Meal names |
| `body` | `.system(.body)` | | Copy |
| `numeric` | rounded `.title3` semibold, monospacedDigit | | Row kcal |
| `label` | `.system(size: 11, weight: .semibold).width(.expanded)` uppercase, tracking +0.8 | | "KCAL LEFT", "PROTEIN", meal-type |
| `caption` | `.system(.footnote)` inkSecondary | | Hints |
All via Dynamic Type (`.dynamicTypeSize(...DynamicTypeSize.accessibility2)` cap on `hero`, with `ViewThatFits` fallback to 64pt).

### 1.3 Spacing (4pt base)
`xxs 4 · xs 8 · s 12 · m 16 · l 24 · xl 32 · xxl 48 · hero 64`. Screen gutter: 20. Row vertical rhythm: 16. Section gap: 32.

### 1.4 Radii (concentric)
Device corner ≈ 55 → sheet 38 → large control 28 → row thumbnail 18 → chip 12 → capsule for pills. Rule: inner radius = outer radius − padding. Use `.rect(cornerRadius:, style: .continuous)` and `ConcentricRectangle()` (iOS 26) for anything touching screen edges.

### 1.5 Glass rules
1. Glass is **only for things you touch or that float over live content** (camera, photo). Never for reading surfaces.
2. Max **one** `.regular.tint(...)` per screen, and the tint is always `leaf` or `ember` (state, not decoration).
3. Neighbouring glass controls always live in one `GlassEffectContainer(spacing: 20)` so they merge/split liquidly.
4. Every glass element that appears in two places shares a `glassEffectID(_:in:)` in one `@Namespace` — glass **moves**, it does not fade.
5. `.interactive()` on every tappable glass element.
6. Reduce Transparency → `Glass.identity` fallback + `groundRaised` fill + hairline stroke.

### 1.6 Motion
| Token | Curve | Use |
|---|---|---|
| `snap` | `.spring(duration: 0.28, bounce: 0.15)` | press, toggles |
| `settle` | `.spring(duration: 0.5, bounce: 0.2)` | morphs, sheet content |
| `fill` | `.spring(duration: 0.9, bounce: 0.05)` | plate fill / arcs |
| `breath` | `.easeInOut(duration: 2.4).repeatForever(autoreverses: true)` | analyzing only |
| numbers | `.contentTransition(.numericText(value:))` inside `withAnimation(.snap)` | every changing number |
Reduce Motion: morphs become 0.2s cross-fades; `breath` disabled; plate fill jumps with opacity.

### 1.7 Haptics (`.sensoryFeedback`)
| Moment | Feedback |
|---|---|
| Camera becomes level & in range | `.alignment` (once per transition to ready) |
| Shutter | `.impact(weight: .medium)` |
| Each food identified in analysis | `.selection` |
| Review appears | `.success` |
| Portion slider crosses 10 g | `.selection` |
| Save → plate fills | `.impact(flexibility: .soft, intensity: 0.7)` then nothing |
| Going over target | `.warning` (once per day) |

---

## 2. Components (Design folder)
- `PlateView(eaten:, target:, macros:, style: .full/.compact/.lens)` — replaces `CalorieRing` + `MacroBar`. Disc = `Circle().fill(leaf.opacity(fill))` rising like liquid from bottom via `Canvas` wave clipped to circle; rim 10pt with three macro arcs (`Circle().trim`) in protein/carbs/fat, gaps of 2°. Centre: `hero` number + `label` "KCAL LEFT"/"KCAL OVER". Over target: fill turns ember, surface tension wobble via `keyframeAnimator` (one time).
- `ScanOrb` — the one prominent glass object: 72pt circle, `.glassEffect(.regular.tint(leaf.opacity(0.35)).interactive(), in: .circle)`, `glassEffectID("scan", in: ns)`.
- `GlassPill` — capsule glass for guidance/meal type.
- `NumberText` — `Text(value, format: .number)` + numericText + monospacedDigit.
- `ConfidenceDot` — 6pt dot leaf/honey/ember + VoiceOver text; replaces coloured badges.
- `ItemRow` — no card; hairline separator; thumbnail/emoji left, name, grams, kcal right.
- Delete: `GlassCard`, `SectionTitle`, `Badge` (or keep Badge only internally for "Demo").

---

## 3. Screens

### 3.1 Onboarding — "Drawing the plate"
```
┌─────────────────────────┐
│                         │
│        ◯  (outline)     │  plate drawn stroke-by-stroke (trim 0→1)
│                         │
│  Lose weight by just    │  display, left aligned
│  taking a photo         │
│                         │
│  ●○○○                   │  page dots (hairline)
│        [ Continue ]     │  glassProminent, full width, id onboardingContinue
└─────────────────────────┘
```
Steps: Welcome → About you → Your goal → Your daily plan. The plate outline sits at top of every step and **gains information**: About you → rim appears; Goal → pace picker bends the rim thickness; Plan → plate fills to the target and the number counts up (`planTarget`, `display`→`hero`, numericText from 0). Then the plate *moves* (matchedGeometryEffect, namespace owned by RootView) into Today's plate position — the first "of course" moment.
- Inputs: sex as two large glass segment buttons in one `GlassEffectContainer` (selection morphs between them with `glassEffectID("sex")`); height/weight/age as rounded wheel `Picker(.wheel)` inline, not forms; pace chips "Gentle 0.25 / Steady 0.5 / Faster 0.75" (keep strings) as glass capsules merging.
- APIs: `TabView(.page(indexDisplayMode: .never))` or manual step state + `.transition(.asymmetric(.push(from: .trailing), .push(from: .leading)))`, `phaseAnimator` for outline draw, `.sensoryFeedback(.selection, trigger: step)`.
- vs today: stops being four forms on cards; becomes one object growing.

### 3.2 Today — "The plate"
```
 Today                       ⌕      (inline title, search glass button)
┌─────────────────────────┐
│          ╭───╮          │
│       ╭─ 1,240 ─╮       │  PlateView.full, 300pt, centered
│       │ KCAL LEFT│      │  rim arcs = protein/carbs/fat
│       ╰─────────╯       │
│   760 eaten · 2,000     │  caption, one line
├─────────────────────────┤
│ BREAKFAST  08:12        │  label + time
│ [img] Oats & berries 380│  ItemRow, no card
│ LUNCH      13:05        │
│ [img] Chicken bowl   620│
│                         │
│  (scroll → plate shrinks to 64pt compact in nav bar)
└─────────────────────────┘
   [ Today  Progress  Settings ]   tab bar (minimizes on scroll)
   (  ◉ Scan a meal  )            tabViewBottomAccessory — ScanOrb capsule
```
- Signature: **scroll-to-compact**. As you scroll, the plate shrinks and docks into the top-leading nav area (`onScrollGeometryChange` → scale 1→0.22, `matchedGeometryEffect` to a toolbar slot). Meal rows use `.scrollTransition { $0.opacity($1.isIdentity ? 1 : 0.4).scaleEffect($1.isIdentity ? 1 : 0.97) }`.
- After saving a meal: the meal's photo thumbnail flies from Review into its row (`matchedTransitionSource` + `.navigationTransition(.zoom)` in reverse), then the plate fill rises (`fill` spring) and the hero number rolls (numericText). One `.impact(soft)`.
- Empty state: plate outline only, dashed rim; text "Snap your first meal" (keep) + one line of copy; button `scanFirstMeal` (glassProminent, leaf tint). The accessory remains.
- Connection problem: a single glass pill under the plate, ember-tinted, tap → Settings.
- Delete: `.swipeActions` on `List`-less rows via `contextMenu` (keep) plus swipe using `List` with `.listStyle(.plain)` and `.listRowBackground(.clear)`.
- Keep ids: `calorieRing` (on PlateView), `scanFirstMeal`, `scanAccessory` (bottom accessory, label "Scan a meal"). Search toolbar button stays ("Add food by search").

### 3.3 Scan camera — "The lens"
```
┌─────────────────────────┐
│ (×)        (Lunch ▾) 3D │  top GlassEffectContainer: close, meal-type pill, LiDAR glyph
│                         │
│     ╭───────────────╮   │
│    ╱  live AR feed   ╲  │  circular "plate lens" mask guide (not brackets):
│   │   surface mesh    │ │  soft 1pt white ring, outside dimmed 35%
│    ╲  dots on food   ╱  │
│     ╰───────────────╯   │
│   ( ◐ Hold level · 34 cm )  guidance pill, id guidance
│                         │
│   (▣)     ( ◉ )     (✎) │  bottom GlassEffectContainer: library, shutter, note
└─────────────────────────┘
```
- Signature: **the lens aligns.** The ring guide tightens and turns leaf when tilt < 5° and distance in range: ring stroke `trim` + `.animation(.settle)`, the level bubble in the pill slides to center, `.sensoryFeedback(.alignment, trigger: ready)`. The shutter's inner disc scales 0.92→1 with `symbolEffect(.bounce)`-like `phaseAnimator` when ready.
- The Today accessory ScanOrb morphs into the shutter: `glassEffectID("scan", in: ns)` across the fullScreenCover isn't possible, so use `.navigationTransition(.zoom(sourceID: "scan", in: ns))` with `.matchedTransitionSource(id:"scan", in: ns)` on the accessory button — the orb grows into the camera.
- Keep text "Fit every plate and side inside the frame" (the reticle copy, now shown in the pill for 3s at open), "Demo photo — this device has no AR camera", "Tap the shutter to try the demo". Keep ids `shutter`, `guidance`.
- Distance number: `contentTransition(.numericText())`.

### 3.4 Analyzing — "The plate reads"
```
┌─────────────────────────┐
│  ╭───────────────────╮  │  captured photo, circular crop (same lens), 320pt
│  │  • chicken  • rice │  │  labels pop in at detected positions
│  ╰───────────────────╯  │
│   ✓ Measuring depth     │
│   ◌ Identifying each food│  current step, shimmer text
│   ○ Counting calories   │
└─────────────────────────┘
```
- Signature: a light sweep rotates **around** the circular photo (AngularGradient mask rotating under `breath`), not a scanning bar. As each food is found, a small glass pill springs out from its location (`.transition(.scale.combined(with: .opacity))`, `.sensoryFeedback(.selection)`).
- Active step text uses a custom `TextRenderer` ("ShimmerRenderer") that sweeps opacity per glyph run; completed steps get `Image(systemName:"checkmark").symbolEffect(.drawOn)` (iOS 26) / `.contentTransition(.symbolEffect(.replace))`.
- Step titles unchanged; **"Identifying each food" must remain a plain static text** (the renderer does not change the accessibility string). Keep id `analysisSteps` on the step list container.
- Failure: steps list replaced by ember pill + "Try again" glass button; photo keeps.

### 3.5 Review — "Slices"
```
┌─────────────────────────┐
│ (×)                (✓ Save) │  saveMeal = glassProminent leaf, top trailing
│  ╭─ photo lens with ─╮  │
│  │ slices overlay    │  │  each food a coloured wedge outline on photo
│  ╰───────────────────╯  │
│        640 kcal         │  hero, id reviewTotal
│    likely 560–720       │  caption
│  ───────────────────    │
│  ● Grilled chicken breast   106 g   176 │  ItemRow; tap expands inline
│      [━━━━━━●━━━━] 92–120 g            │  portion slider in expanded row
│  ● Rice                     150 g   195 │
│  + Add food                             │
│  Estimates, not medical advice. Tap an item to adjust it.
└─────────────────────────┘
```
- Signature: **tap an item → its slice lifts**. The tapped row expands in place (no sheet), the corresponding wedge on the photo brightens while others dim (`matchedGeometryEffect` highlight), portion slider drags change grams and the hero total rolls with `numericText`, `.sensoryFeedback(.selection)` every 10 g. Range 92–120 g drawn as a tinted track segment behind the slider — the uncertainty is visible, honest.
- Confidence: `ConfidenceDot` before the name.
- Keep ids/text: `saveMeal`, `reviewTotal`, item names as plain `Text` (e.g. "Grilled chicken breast" must be a tappable static text), "Estimates, not medical advice. Tap an item to adjust it.". If the existing adjust sheet is kept for complex edits (swap food), the tap still must work on the staticText.
- Save: button morphs (glassEffectID) into a checkmark, then dismiss; Today plays the fill.

### 3.6 Food search — sheet
- `.sheet` with `.presentationDetents([.medium, .large])`, `.presentationBackground(.clear)` so the system glass sheet shows. `.searchable` placed `.toolbar` with autofocus (`searchFocused`). Results as plain rows: name, "N kcal/100 g" caption. Selecting a row expands grams stepper inline (keep "g" unit text), "Add" glassProminent. Rows use `scrollTransition` fade. Empty query: recent foods as glass chips in a `GlassEffectContainer` flow.

### 3.7 Barcode
- Same lens language as Scan but a wide rounded rect (radius 28) because packs are rectangles; keep copy "Point at the barcode on the pack". On detect: rect snaps to barcode bounds (`.settle`), `.sensoryFeedback(.success)`, product card rises as a glass sheet (detent .medium): name, "Per 100 g: …" line, grams field with "g eaten", Add. Keep "Data: Open Food Facts (ODbL)" and the unavailable ContentUnavailableView copy.

### 3.8 Progress — "Stacked plates"
```
 Progress                        (+ Log weight)  logWeight
   78.4 kg  ↓0.6 this week       display + caption
   TREND WEIGHT
   ╭ Swift Charts line, trend smoothed, raw points faint ╮  id weightChart
   ───────────────────
   THIS WEEK   ◔ ◑ ◕ ● ◑ ◔ ◯     seven mini plates (PlateView.compact 36pt)
   Your burn: ~2,310 kcal a day  + explanatory copy (keep strings)
```
- Signature: the week as seven tiny plates — the same object, far away. Tap one → it `matchedGeometryEffect`s up to a 160pt plate with that day's meals below.
- Chart: `Chart { AreaMark (leaf gradient to clear), LineMark(interpolation: .catmullRom) for trend, PointMark opacity 0.25 }`, `.chartXSelection` with glass readout pill. Logging weight: glass sheet with big rounded wheel (`display`), "Weigh in the morning, after the bathroom, before eating." kept.
- Keep id `logWeight` (toolbar button, glass), `weightChart`, tab title "Progress".

### 3.9 Settings
- Standard `Form` (familiar is correct here — receding). `.scrollContentBackground(.hidden)` on `ground`. Section headers in `label` style. Connection status row: SF Symbol with `.symbolEffect(.pulse)` while testing, then `.contentTransition(.symbolEffect(.replace))` to checkmark/xmark. Keep all strings ("Test connection", "AI analysis", "Hints for the AI", disclaimers, demo toggle copy). Tab title "Settings".

---

## 4. Must-keep contract (AppUITests/WalkthroughUITests.swift)

Accessibility identifiers (exact):
- `onboardingContinue` — button, present on all 4 onboarding steps
- `planTarget` — **staticText** (element type Text, not a button/group) on plan step
- `scanFirstMeal` — button on empty Today
- `scanAccessory` — button (tab bar bottom accessory) on Today
- `shutter` — button in camera
- `saveMeal` — button in Review
- `logWeight` — button on Progress

Static texts / labels (exact):
- `"Identifying each food"` — staticText visible during analysis
- `"Grilled chicken breast"` — tappable staticText in Review (demo data)
- Tab bar button titles `"Progress"` and `"Settings"` (tab bar buttons, or fallback buttons with those labels); keep `"Today"` too.

Also in code and worth keeping (not asserted by tests but referenced): `calorieRing`, `guidance`, `analysisSteps`, `reviewTotal`, `weightChart`.

Launch args to honour: `-uiTest`, `-resetState`, `-seedDemoData`; env `LW_DEMO_PHOTO`. Timing: `scanAccessory` must exist ≤25 s; plate intro animations must not block hit-testing of these buttons (no `.allowsHitTesting(false)` during animation, no overlay on top).

## 5. Build order
1. Theme + tokens, Daylight ground, delete GlassCard usages.
2. PlateView + Today (compact-on-scroll).
3. Scan lens + zoom transition from accessory.
4. Analyzing renderer; Review slices + inline adjust.
5. Onboarding plate drawing + morph into Today.
6. Progress mini plates; Search/Barcode/Settings polish.
7. Run WalkthroughUITests; check Reduce Motion / Reduce Transparency / AX5 type.
