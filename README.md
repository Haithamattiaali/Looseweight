# Looseweight

Lose weight by just taking a photo of your meal. iPhone app, iOS 26 Liquid Glass design.

The iPhone measures the food on the device (ARKit, LiDAR, Vision). Claude names each food and turns the measurements into grams. Calories come from a USDA-based food table, and the app re-checks the arithmetic.

| Step | Where | What happens |
|---|---|---|
| 📐 Find the table and true scale | iPhone (ARKit) | table plane, camera height and tilt, cm per pixel |
| 📡 Measure in 3D | iPhone (LiDAR, Pro models) | depth fused over ~1 s → height map → volume of each food |
| 👁️ Read the photo | iPhone (Vision) | separate objects, food labels, label text, barcodes, blur check |
| 🤖 Identify and weigh | Claude (newest Opus) | names foods, picks USDA matches, volume × density → grams |
| ✅ Check | App | database nutrients, energy ranges, volume × density re-computed |
| 🙋 Confirm | You | grams with a low–high range; one tap to adjust |

Details: [docs/SPEC.md](docs/SPEC.md)

## Run it on your iPhone

Needs a Mac with Xcode 26 or newer.

```bash
brew install xcodegen
xcodegen
open Looseweight.xcodeproj
```

In Xcode: select the **Looseweight** target → **Signing & Capabilities** → choose your team → pick your iPhone → **Run**.

LiDAR 3D measuring needs an iPhone Pro (12 Pro or newer). Other iPhones still get the ARKit table scale.

## Connect the AI

Settings → **AI analysis**:

| Option | Use it for |
|---|---|
| Demo | Try the app offline with a real weighed sample plate |
| My Anthropic API key | Your own testing (the key stays in the iPhone Keychain) |
| Looseweight Cloud | Production: the key stays on a server — deploy [`proxy/`](proxy/README.md) |

## Tests

| Part | Command |
|---|---|
| Core engine (runs on Linux and macOS) | `cd Packages/LooseweightKit && swift test` |
| iPhone app (simulator, with screenshots) | `bash scripts/ci/macos.sh` |
| Proxy | `cd proxy && npm ci && npm test` |

CI runs all three on every push (`.github/workflows/ci.yml`). The iPhone job uploads screenshots and a screen recording as the **proof** artifact.

## Layout

```
App/                      SwiftUI app (screens, ARKit capture, Vision, SwiftData)
AppTests/ AppUITests/     unit tests and the screenshot walkthrough
Packages/LooseweightKit/  core engine: food table, depth geometry, weight-loss math, Claude loop
proxy/                    Cloudflare Worker that keeps the API key off the phone
scripts/                  food-table builder and CI scripts
```

## Data and licences

- Food table: USDA FoodData Central SR Legacy (public domain) via the TempoLife food dataset, CC-BY-4.0. Rebuild with `python3 scripts/build_food_db.py`.
- Packaged food: Open Food Facts (ODbL), looked up by barcode.
- Tests and demo photo: Nutrition5k (Google Research) plates with weighed calories, downloaded at test time, not stored here.

Looseweight gives estimates to support healthy weight loss. It is not a medical device.
