# Looseweight — build spec

> Goal (owner's words): *"an app that will enable users to lose weight by just logging the calories accurately by camera (very accurately). The app UI is iOS Liquid Glass."*
>
> Product shape: **Log or Plan.** Every meal photo is either a log (what I ate) or a plan (what I'm about to eat).
> **Units are a setting with two modes** (see §1b). **Everyday** (default, the only mode onboarding teaches):
> bites, sips, pieces, servings and fractions of an item — no grams anywhere, not for food and not for macros.
> **Precise** (opt-in in Settings) adds grams. Grams always exist inside the engine.

## 1. What the user does

| Step | Screen | What happens |
|---|---|---|
| 1 | Onboarding | Welcome, "Count food the way you eat it" (bites, sips, pieces, a share, servings), sex, age, height, weight, goal weight, activity, pace → daily calorie target. Never mentions food weights |
| 2 | Today | The plate (kcal left), protein / carbs / fat as rim arcs and bars with "on track / a little short / short / over", confirmed meals of the day |
| 3 | Scan | Camera. Hold the phone flat over the plate and tap. A ~1.8 s sweep follows (like a Live Photo): LiDAR depth keeps fusing from every angle and extra views are collected |
| 4 | Analyzing + choice | While Claude finds and measures every food, two glass buttons ask: **Log** (what I ate) or **Plan** (what I'm about to eat) |
| 5a | Review (Log) | Each item as "about 7 bites", "5 sips", "6 pieces" or "2/3 of the piece", with range and confidence. Nudge ±1 bite/sip/piece or ¼ of the item. Save → counts today |
| 5b | Plan | For each food: "Rice: 6 bites", "Chicken: 2/3 of the piece", "Juice: 5 sips", "Bread: skip". Save plan → Inbox |
| 6 | Inbox (tab with badge) | Planned meals wait here. Ate it all as planned / Ate part (1/4, Half, 3/4) / Didn't eat. Only confirmed amounts are logged and count toward today |
| 7 | Reminder | A gentle sheet at the next app open (plan ≥ 15 min old) and a local notification about an hour after planning |
| 8 | Progress | Weight log, trend line, real daily burn (learned from your data), goal date |

Barcode and manual search add food by **servings** (½ steps), shown with a bites/sips/pieces hint. In Everyday there is no grams field anywhere; Precise adds one.

## 1b. Units modes (`UnitsMode`, `AmountFormatter`)

One setting, one formatter. `UnitsMode` (`everyday` default, `precise`) is stored by `AppModel` in UserDefaults
(`lw.unitsMode`, cleared by `-resetState`) and passed to every view as `\.unitsMode`. `AmountFormatter` in
LooseweightKit (Foundation only) turns internal grams into text for either mode; every screen and the CSV export use it.
Settings row: **Units: Everyday (bites, sips, pieces) / Precise (grams)** with a one-line explanation.

| Screen | Everyday | Precise adds |
|---|---|---|
| Onboarding | Counting step; macro targets as "% of calories" | (onboarding never offers Precise; editing the profile later shows "120 g") |
| Today | Macro bars + "on track / a little short / short / over" | "62 of 120 g · on track" |
| Review | "about 7 bites", "likely 5 bites to 9 bites", macros as "% of your day" bars | "· 84 g" on amounts and ranges, grams field in the editor, macro grams |
| Plan / Inbox | "6 bites", "2/3 of the piece", "Skip"; plan macros as "% of your day" | "· 90 g" after each instruction, macro grams |
| Search / Barcode | "1½ servings" + bites hint, kcal a serving | "· 225 g", grams field, kcal per 100 g, barcode macros in grams |
| Progress | Body weight only (no food amounts) | — |
| CSV export | `date,meal,food,portion,kcal,method` | `grams,protein_g,carbs_g,fat_g` columns |

## 1a. Planning (MealPlanner)

- Budget = what is left today from **confirmed** meals (targets − eaten, never below 0), times the meal's share:
  breakfast 35 %, lunch 50 %, dinner 100 %, snack 25 % — the rest stays for later meals.
- Each food moves in its own unit: one bite, one sip, one piece, or nice fractions of a single item
  (¼, ⅓, ½, ⅔, ¾, all). Greedy: protein still needed counts triple, fibre helps, calories never exceed the budget,
  carbs and fat stay within what is left (+8 g / +4 g slack). Never below zero; nothing left → everything "Skip".
- Portion sizes (`PortionSizes`): drinks → sips of ~20 mL; small countable foods (cherry tomatoes, nuggets, dates,
  falafel…) → pieces; one big item (a chicken breast, a fillet, a sandwich, a banana) → fraction of the piece;
  sauces/oil → fraction of the sauce; everything else → bites (rice/pasta/meat ~15 g, vegetables ~12 g, nuts ~8 g).
- **Unit sliders (Plan and Review).** Every item has a slider in its natural unit (`UnitScale`): bites, sips, pieces
  or slices, servings (½ steps) or fractions of one item (¼ ⅓ ½ ⅔ ¾ all). Each stop shows the unit words and
  "= X kcal"; the meal total and "N kcal left today after this" / "N kcal over today" (`BudgetFit`) update live with
  a haptic tick per step. The AI's suggestion is a marker and snap point ("suggested: 4 bites"). Plans stop at what
  is there; Review runs past it (the person may have eaten more). Everyday labels never show grams; Precise adds them.
  Accessibility id `unitSlider` (adjustable), `budgetFit`.
- **Drinks are first-class.** The analysis answer gives every item `kind: food|drink`; drinks also get
  `drink_unit` (sip / cup / glass / can / bottle / mug) and `ml_per_unit`. The prompt asks for every drink in view
  (water, juice, soda, coffee, tea, milk, smoothies, shakes, soups served to drink). `NutritionResolver` also catches
  drinks by name, falls back to the unit's default volume (glass 250, can 330, mug 300, cup 240, bottle 500 mL) and
  keeps mL internal. A drink is counted in sips (~20 mL) and, for a whole amount, in its container ("1 glass",
  "1 1/2 cans"). The on-device food gate accepts cups, mugs, glasses, bottles and cans. The demo meal has a glass of juice.
- `PlannedMeal` + `PlanConfirmation` (pending / ate as planned / ate part / didn't eat) + `PlanInbox` reminder rules
  live in LooseweightKit; the app stores them as `PlannedMealRecord` (SwiftData) and logs the eaten share on confirmation.

## 2. How the accuracy works

Calories = **grams** × **calories per gram** (inside the engine; the user sees bites, sips, pieces and fractions). Both halves are grounded, not guessed.
The iPhone measures on the device; the AI names the food and does the judgment.

```mermaid
flowchart LR
  subgraph Phone["iPhone, on device"]
    AR[ARKit\ntable plane + true scale\ncamera pose]
    LI[LiDAR depth\nfused over the ~2 s sweep]
    SW[Sweep\nsharpest extra views\nfrom new angles]
    VI[Vision\nitem masks, labels,\ntext, barcodes, blur]
    HF[Height field\n4 mm grid on the table]
    AR --> HF
    LI --> HF
  end
  HF --> MS[Per-item area cm²,\nvolume mL, heights]
  SW --> C
  VI --> MS
  MS --> C[Claude vision]
  C -- search_foods --> DB[(USDA-based food table)]
  C -- measure_region --> HF
  C -- zoom_photo --> Z[Full-res crop]
  C --> J[JSON: items, food ids,\ngrams, low/high, confidence]
  J --> N[App math:\ngrams × per-100 g values\n(internal only)]
  N --> R[Log: review in bites/sips/pieces]
  N --> P[Plan: MealPlanner → Inbox → confirm]
  R --> M[(Portion memory)]
  M -. hints next time .-> C
```

**On the iPhone (free, instant, private)**

| Power | Devices | Output |
|---|---|---|
| ARKit world tracking + horizontal plane | every supported iPhone | table plane, camera pose, cm-per-pixel at the plate, plate diameter, item footprint area (cm²) |
| LiDAR scene depth, fused over the capture sweep | Pro iPhones | height field above the table → item volume (mL), heights, plate floor — from more viewpoints |
| Capture sweep (~1.8 s after the shot) | every AR iPhone | sharpest frames from the most different angles (`SweepSelector`) sent as extra images |
| Vision foreground instance masks | all | separate objects (plate, bowl, cup, items) as numbered regions |
| Vision image classification | all | quick food label hints; the **food gate** (below) |
| Vision text recognition | all | nutrition labels and packaging text, read exactly |
| Vision barcodes → Open Food Facts | all | exact per-100 g for packaged food |
| Blur, tilt, distance, steadiness checks | all | retake prompts and a live bubble level before the shot |

**Food gate (only food is analysed)**

- *Live, before capture:* with the AR camera open, `VNClassifyImageRequest` runs on a small copy of the camera image about every 0.5 s, off the main thread (no `ARFrame` is kept). `FoodPresenceDetector` (LooseweightKit) scores each frame by its strongest food label (allowlist: food, meal, dish, fruit, vegetable, bread, drink, beverage, dessert and similar; excluded look-alikes such as "food processor"), averages the last 4 frames and applies hysteresis (food at ≥ 0.30, not-food below 0.15 after at least 3 frames; in between keeps the last verdict, unknown counts as food). When not food: the pill reads "This doesn't look like food — point the camera at your meal" (`notFoodNotice`), the frame brackets turn amber, one warning haptic, and the shutter is dimmed and disabled. After 2 s an "It's food" button (`itsFoodOverride`) overrides until the camera sees food again. Without an AR camera (simulator, demo, UI tests) the gate never runs.
- *Library photos:* the same classifier check runs on a picked photo; if it is not food, an alert offers "Choose another" or "Analyse anyway".
- *AI backstop:* the output schema has `no_food` and `no_food_reason`. When the photo has no food or drink (or no loggable item is left) `MealAnalyzer` throws `ClaudeError.noFood`, and the analysis screen shows "No food found in this photo" with Retake. An empty review or a 0 kcal meal is never saved.

**In the cloud (Claude, newest Opus model resolved at runtime from `/v1/models`)**

1. Sees the upright photo, a numbered overlay of the on-device regions with a 5 cm scale bar, and the on-device measurement report.
2. Names every item and calls `search_foods` to pick a database id. Nutrients come from the database. If nothing fits, its own per-100 g estimate is used and flagged "AI estimate". Merged database rows carry an energy range; the model may choose inside it, never outside.
3. Turns measured volume into grams with food density (or measured area × estimated thickness without LiDAR; scale cues and counting without ARKit). Calls `measure_region` with its own polygon when an item is not a separate on-device region.
4. Adds hidden calories as their own items: oil, butter, dressings, sauces.
5. Calls `zoom_photo` for a full-resolution crop when detail is unclear.
6. The app re-checks the arithmetic (volume × density) and the database match.

**Then the user** sees each amount as bites, sips, pieces or a fraction of the item, with a likely range, and can nudge it one unit at a time. Corrections become portion memory (grams, internal) and are sent as hints next time. Notes shown to the user never mention grams (the prompt asks for pieces/bites/plain words).

## 3. Weight-loss engine

- BMR: Mifflin–St Jeor. TDEE = BMR × activity factor.
- Target = TDEE − pace × 7,700 kcal/kg ÷ 7. Floors: 1,200 kcal (female) / 1,500 kcal (male). Pace capped at 1 % body weight per week. Goal weight below BMI 18.5 is refused.
- Weight trend: exponential moving average (α = 0.1 per day, gap-aware).
- Adaptive TDEE (after ≥ 14 days, ≥ 10 logged days): intake − trend slope × 7,700. Blended with the formula as data grows.
- Protein target 1.6 g/kg; fat 30 % of energy; carbs the rest.

## 4. Parts

| Part | Path | Tech | Tested by |
|---|---|---|---|
| Core engine | `Packages/LooseweightKit` | Swift 6, Foundation only (runs on iOS, macOS, Linux) | `swift test` on Linux + macOS CI |
| iPhone app | `App/` | SwiftUI iOS 26 (Liquid Glass), SwiftData, ARKit + LiDAR, Vision, VisionKit, Swift Charts | Xcode unit + UI tests on iOS Simulator in CI, screenshots |
| API proxy | `proxy/` | Cloudflare Worker (TypeScript) | vitest |
| Accuracy eval | `Packages/LooseweightKit/Sources/lw-eval` | Swift CLI on Nutrition5k (real dishes with weighed calories + depth) | runs when an API key is present |
| CI | `.github/workflows/ci.yml` | GitHub Actions (Linux + macOS runners) | — |

## 5. AI connection modes (Settings)

| Mode | For | Key location |
|---|---|---|
| Looseweight Cloud (proxy) | Production | Server secret in the Worker; app sends an app token |
| My Anthropic key | Personal / testing | iOS Keychain on the device |
| Demo | Simulator, UI tests, first look | No network; canned result for the bundled sample |

## 6. Claude request contract

- `POST /v1/messages`, non-streaming, `max_tokens` 16,000, adaptive thinking (model default), `output_config.effort` = `high` (Precise) or `medium` (Fast), `output_config.format` = analysis JSON schema, `fallbacks: "default"` (beta `server-side-fallback-2026-07-01`) so a false-positive refusal is retried on the recommended model.
- Tools: `search_foods` (always), `measure_region` (only with depth), `zoom_photo` (only with a full-res original). `tool_choice` auto. Loop ≤ 6 turns.
- Append-only history; assistant content is echoed back byte-for-byte. System prompt + tools are cached (`cache_control`).
- `stop_reason == "refusal"` → friendly error, no partial result.

## 7. Evidence so far

| Check | Result |
|---|---|
| Synthetic scenes (exact ray-cast depth, like LiDAR) | volume error ≤ 6 % in one frame, ≤ 8 % fused from 12 noisy frames; plate floor found within 2.5 mm; true area without LiDAR within 10 % |
| Real depth-camera plates (Nutrition5k, 26 overhead shots, crude colour mask) | plausible volumes, median 0.57 g/mL; volume alone correlates r = 0.50 with weighed mass because food densities differ (salad ≈ 0.1, meat ≈ 1.0) — the model supplies density per food |
| Full AI accuracy (`lw-eval ai --compare`) | needs an API key; reports calorie error with and without on-device measurements |

## 8. Privacy & safety

- Photos go only to the chosen AI connection. Data stays on the phone (SwiftData). Export and delete-all in Settings.
- Not medical advice. Targets never go below the floors in §3.

## 9. Out of scope for v1

App Store release, accounts/sync, HealthKit sync, Apple Watch, widgets, Arabic UI.
