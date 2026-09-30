# Looseweight — Design Direction ("Aurora")

## 0. Purpose and the one idea

**Purpose.** A person trying to lose weight should know what a meal costs them in the three seconds between
sitting down and taking the first bite — and enjoy opening the app to find out.

**The single idea:** *An AI that feels alive, glowing over living colour.* Every screen floats Liquid Glass over an
animated aurora of saturated colour. The AI has a body — a breathing orb — that appears whenever it looks or thinks,
and its answers stream in item by item. Food and drink are colour: every food keeps its own vivid colour on every
screen, every macro has its own hue.

The owner rejected the previous warm off-white "day is a plate" direction as dull. What changed:

| Before ("The Plate") | Now ("Aurora") |
|---|---|
| Warm paper ground, still, tinted ≤6 % | Dark-first ground with an animated 3×3 `MeshGradient` aurora that drifts and shifts with the time of day and the meal |
| One accent (leaf), everything else neutral | Saturated palette: mint, cyan, violet, magenta, coral, amber, lime, electric blue; per-food and per-macro colour coding |
| Glass for controls only | Liquid Glass surfaces (cards, rows, sheets) floating over colour, tinted by the food they hold |
| Analysis = light sweeping a photo border | Breathing AI orb + rising sparks + shimmer over the full photo, steps streaming in |
| Semibold 88 pt numbers in ink | Heavy 96 pt rounded numbers with ink-to-colour gradients and soft glows |
| Hairline lists | Glass cards that stream in one after another |

Kept on purpose: full-frame capture brackets on the camera (never a circle — everything in the frame is analysed),
the on-device food gate, the Log / Plan / Inbox flow, Everyday units (no grams unless Precise), the plate as the
Today hero, and every accessibility identifier.

## 1. Design tokens (`App/Design/Theme.swift`)

### 1.1 Palette (dark-first; the app sets `.preferredColorScheme(.dark)`, light values stay vivid)
| Token | Dark | Light | Use |
|---|---|---|---|
| `ground` | #07060F | #F3F0FF | Base under the aurora |
| `groundRaised` | #16132B | #FFFFFF | Reduce Transparency fallback for glass |
| `ink` / `inkSecondary` / `inkTertiary` / `hairline` | white @ 100 / 72 / 46 / 14 % | #0E0B1F @ 100 / 64 / 40 / 10 % | Text and tracks |
| `leaf` (go, room left, save) | #2EF2B0 mint | #00A67E | Remaining kcal, Log, save |
| `ember` (over) | #FF5C86 | #F0265E | Over target, low confidence |
| `honey` = `carbs` | #FFC23D | #F08C00 | Carbs, medium confidence, not-food camera state |
| `protein` | #FF5FA2 | #E8267A | Protein |
| `fat` | #5AA2FF | #2F6BFF | Fat |
| `violet` | #8B6CFF | #5B3DF5 | The AI, Plan, Inbox |
| `cyan` | #22E1FF | #0096C7 | Drinks, Progress, depth |
| `magenta`, `coral`, `lime` | #FF5CF4, #FF7A6B, #B6F35A | | Food palette, aurora |

- `aiColors` / `aiGradient`: violet → cyan → mint → magenta. Used by the orb, the scanning light, suggestion marks,
  photo borders and the camera brackets when ready.
- `foodColor(for:isDrink:)`: a stable hash of the food name into `foodPalette` (coral, amber, lime, mint, cyan, blue,
  violet, magenta); drinks are always cyan. The same food is the same colour on the photo outline, its row, its dot,
  its slider and the Inbox.
- `sweep(color)`: a 55 %→100 % gradient of one colour for bars, arcs and slider fills.

### 1.2 Aurora ground (`DaylightGround(mood:energy:)`)
A 3×3 `MeshGradient` over `ground`, interior points drifting on slow sines inside a `TimelineView` at ≤20 fps
(paused when the scene is inactive or Reduce Motion is on). Colours come from the part of the day — dawn
honey/coral/magenta, day cyan/mint/blue, dusk magenta/coral/violet, night violet/blue/magenta — and `mood` pulls the
top-left corner toward the screen's colour (violet while the AI works, the lead food on Review, ember when over).
`energy` sets the drift (0.2 Settings/Search, 0.35 Today, 1 Analysis). A bottom fade to `ground` keeps lists legible.

### 1.3 Type
SF Pro Rounded, big and confident. `hero` 96 heavy (tracking −3) for kcal left / meal totals / plan target;
`display` 60 bold for weight; `screenTitle` 34 heavy for step and empty-state titles; `numeric` rounded title3 bold
for row numbers, tinted with the food's colour; `label` 11 pt expanded caps, often in the section's colour.
Hero numbers use an ink → accent vertical gradient with a soft glow of the same accent.

### 1.4 Glass
Liquid Glass surfaces float over the colour: `glassSurface(tint:radius:)` (a `ControlGlass` rounded rectangle,
tint at 28 %). Cards: analysis steps, review items, plan items, Inbox plans, Progress panels, search results, the
barcode product. Buttons use `.glass` / `.glassProminent` tinted with their meaning (Log mint, Plan violet).
Reduce Transparency → `groundRaised` fill + hairline.

### 1.5 Motion and the AI presence (`App/Design/AIPresence.swift`)
- `AIOrb(size:isActive:)`: two counter-rotating angular gradients of `aiColors`, a blurred halo and a specular
  highlight, breathing (±7 % active, ±3 % idle). Appears on the analysis photo, beside the running step, inside the
  capture sweep ring, in the scan accessory, on the empty Today card and behind the onboarding plate.
- `SparkleField`: one `Canvas` of rising, twinkling sparks over the photo while the AI reads it.
- `shimmer()`: a light band sweeping across the photo during analysis.
- `streamIn(index)`: results rise, un-blur and fade in 90 ms after the one before (analysis steps, review items,
  plan items, Inbox cards, search results, Progress panels).
- Numbers change with `.contentTransition(.numericText)` and the `snap` spring. Reduce Motion freezes every
  `TimelineView` and shows streamed content at once.

### 1.6 Haptics
Selection tick per slider step and per finished analysis step; alignment when the camera is ready; medium impact on
the shutter; warning when the food gate blocks or a day goes over; success on save / plan / confirm.

## 2. Components (`App/Design`)
`Theme`, `DaylightGround` (aurora), `AIOrb`, `SparkleField`, `Shimmer`, `StreamIn`, `FoodDot`, `glassSurface`,
`glow`, `ControlGlass`, `GlassPill`, `PlateView` (glass disc with a cyan→mint liquid and glowing gradient macro
arcs; ember→magenta when over), `MacroProgress` (gradient bars with glow), `UnitSlider` + `BudgetFitBar`.

### 2.1 Unit slider (`UnitSlider`)
A custom track in the food's colour: filled gradient capsule, one tick per step (up to 30), a glass-white thumb
with a coloured glow, and a sparkle marker at the AI's suggestion. Above it: the unit words ("3 pieces",
"5 sips", "1 glass", "Half the piece") and "= X kcal" in the food colour, both animating. Below: a tappable
"✦ suggested: 4 bites" that snaps back to the suggestion; long scales snap magnetically when the thumb passes it.
Haptic selection tick per step; VoiceOver: adjustable, value = unit words + kcal. `BudgetFitBar` shows the meal
against what is left today and turns ember when over.

## 3. Screens
- **Onboarding** — aurora mood per step (violet, cyan, magenta, amber, mint); the AI orb glows behind the plate
  drawing; gradient headline; coloured icon glows; counting step in a glass card (now with glasses, cans, mugs);
  plan target hero in ink→mint with macro targets in their colours.
- **Today** — aurora by time of day (ember mood when over). The plate is a glass disc with liquid colour and
  glowing macro arcs; meal groups get coloured labels and glass rows; the empty day is a glass card with an idle orb.
  The scan accessory carries a small orb.
- **Scan** — live camera, full-frame brackets (white → mint/cyan/violet gradient with glow when ready, amber when
  the food gate says not food). Shutter glows mint when ready. The capture sweep ring is an AI gradient around a
  small orb.
- **Analysis + Log/Plan choice** — the full photo under a violet veil, sparks, shimmer and the breathing orb; an
  aurora light travels the border. Steps stream in a glass card, the running one led by a tiny orb. Log (mint) and
  Plan (violet) float as tinted glass.
- **Review** — photo outlines in each food's colour (selected glows), gradient hero total, budget bar, glass item
  cards streaming in; drinks show a cup glyph; tapping a card opens its unit slider in the food's colour.
- **Plan** — violet mood, photo with AI border, gradient total, budget bar, one glass card per food with its slider
  and the AI's suggestion marked.
- **Inbox** — violet mood; plans as violet-tinted glass cards with an AI-gradient edge and coloured food dots.
- **Search / Barcode** — glass result cards with food dots, streaming; barcode frame in the AI gradient, product
  card in amber glass.
- **Progress** — cyan mood; gradient weight, magenta→cyan→mint trend line with a glowing area, glass panels.
- **Settings** — calm aurora (low energy), coloured section labels.

## 4. Must-keep contract (AppUITests/WalkthroughUITests.swift)

Accessibility identifiers (exact):
- `onboardingContinue` — button, present on all 4 onboarding steps
- `planTarget` — **staticText** (element type Text, not a button/group) on plan step
- `scanFirstMeal` — button on empty Today
- `scanAccessory` — button (tab bar bottom accessory) on Today
- `shutter` — button in camera
- `saveMeal` — button in Review
- `logWeight` — button on Progress
- `logChoice`, `planChoice` — Log / Plan buttons over the analysis
- `savePlan` — button in Plan; `confirmAteAll` — button in Inbox
- `unitSlider` — every portion slider (adjustable element) in Plan and Review; `budgetFit` — staticText "N kcal left today after this"

Static texts / labels (exact):
- `"Identifying each food"` — staticText visible during analysis
- `"Grilled chicken breast"` — tappable staticText in Review (demo data)
- Tab bar button titles `"Progress"` and `"Settings"` (tab bar buttons, or fallback buttons with those labels); keep `"Today"` too.

Also in code and worth keeping (not asserted by tests but referenced): `calorieRing`, `guidance`, `analysisSteps`, `reviewTotal`, `weightChart`, `planTotal`, `planList`, `notFoodNotice`, `itsFoodOverride`, `noFoodFound`, `noFoodRetake`, `countingStep`, `dayMacros`, `unitSliderSuggestion`.

Launch args to honour: `-uiTest`, `-resetState`, `-seedDemoData`; env `LW_DEMO_PHOTO`. Timing: `scanAccessory` must exist ≤25 s; plate intro animations must not block hit-testing of these buttons (no `.allowsHitTesting(false)` during animation, no overlay on top). `StreamIn` reveals finish within ~1 s and never disable hit-testing; the AI orb, sparks and shimmer are all `allowsHitTesting(false)` / `accessibilityHidden`.

## 5. Accessibility
Dynamic Type everywhere (hero numbers fall back via `ViewThatFits` / `minimumScaleFactor`); Reduce Motion freezes
the aurora, orb, sparks and shimmer and skips stream-in; Reduce Transparency swaps glass for raised fills; colour is
never the only signal (unit words, "over" labels, confidence words stay).
