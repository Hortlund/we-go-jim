# App Store creative assets

| Upload slot | File | Dimensions |
| --- | --- | --- |
| Product page header | [header-3840x1646.png](header-3840x1646.png) | 3840 × 1646 |
| Search result image | [search-result-1920x1280.png](search-result-1920x1280.png) | 1920 × 1280 |

Created on 9 October 2026 with the built-in image generation tool. The designs share WGJ's navy and blue palette, strength-training imagery, and bold white typography. The search creative uses the actual [set-logging screenshot](../AppStoreScreenshots/iPhone/03-log-workout.png) as its compositing reference; it is a generated marketing composition, not an untouched simulator capture.

These files are creative assets, separate from the native screenshots and app preview videos. Exported as opaque PNGs at the supported dimensions provided in App Store Connect. The generated sources were resampled to the upload dimensions; these are not native-resolution renders at those larger sizes.

The text is English. Preview both assets in App Store Connect to check responsive crops and any interface overlays before submission. They have not been uploaded or approved by Apple.

Guidance: [Apple's asset best practices](https://developer.apple.com/app-store/asset-best-practices/). Use a clear focal point, keep important content away from crop edges, and make the app's purpose apparent in search. No prices, URLs, awards, or download badges are included.

## Initial generation prompts


### Header

```text
Use case: ads-marketing.
Create a finished premium App Store product-page header for the native workout tracker "We Go Jim".
Canvas: ultra-wide landscape, 3840 × 1646 pixels, approximately 2.333:1 aspect ratio. Opaque edge-to-edge artwork.
Creative direction: sophisticated strength-training editorial, quiet confidence, very clean, strong typographic hierarchy, a beautifully photographed sculptural black rubber dumbbell and two blue-black weight plates on a matte deep-navy studio floor. Physically plausible gym equipment, subtly knurled steel handle, precise cobalt-blue rim lighting, soft ice-blue highlights. A gentle blue pool of light fades into near-black navy. No busy gym interior, no people, no floating sci-fi panels. Premium tangible materials with restrained glow, not neon cyberpunk.
Composition: balanced, deliberately spacious horizontal design. A compact text group and the equipment form a single central composition, safely inside the middle 70 percent width and middle 65 percent height. Equipment on the right, clean typography on the left with generous breathing room; no objects touching the lettering. Leave outer edges and lower 15 percent quiet for responsive App Store crops.
Text exactly, with no extra words:
"We Go Jim" in very large bold contemporary Swiss-style sans serif, white.
"Every rep counts." below, smaller but clearly readable, muted ice blue.
Use natural sentence case as specified. Typographic edges exceptionally crisp.
No device mockups, no fabricated app UI, no badges, no URLs, no download buttons, no App Store or Apple logos, no awards, no borders, no watermarks. The app's established palette is navy, cobalt, ice blue and subtle cyan. This is the final standalone header artwork, not a presentation board.
```

### Search result

Image 1 was the generated header. Image 2 was the repository's set-logging screenshot linked above.

```text
Use case: compositing.
Create the matching SEARCH RESULT creative for We Go Jim by adapting Image 1 (the header design) into a 1920 × 1280 landscape 3:2 composition. Image 1 is the edit target and visual style to preserve. Image 2 is an actual screenshot from the app to insert faithfully.
Keep the deep navy, cobalt rim light, tactile black gym equipment, quiet premium atmosphere, crisp white Swiss sans-serif typography. Rearrange for the taller 3:2 frame; simplify the equipment to one small dumbbell near the bottom, subordinate to the app itself.
Place a single large, upright, flat rectangular app screenshot on the right, using Image 2 exactly for the screen contents, undistorted aspect ratio. No angled perspective, no extra floating UI, no invented controls or redrawn numbers. Thin dark neutral surround, softly rounded outer corners; no Apple logo or branded device casing. Keep the screenshot legible, approximately 76 percent canvas height, with room all around. It should clearly show logged weight/reps, green completed sets and the rest timer.
On the left, a compact, oversized white headline split over three lines reads exactly:
"Plan."
"Lift."
"Progress."
Above it a small but readable brand label: "We Go Jim"
Below it a clear ice-blue descriptor: "Workout tracking."
No other added copy. Typography must be clean and accurately spelled. Important elements stay within central 82 percent width and 80 percent height, clear of crop edges. Keep lower 10 percent quiet. The result should make it immediately clear this is a workout logging app, with plenty of breathing room. No badges, awards, URLs, pricing, download CTA, watermarks or outer borders. Opaque background. This is a finished standalone App Store search asset, not a presentation board.
```

## Current revision

The header tagline is now "We're all going to make it". Both images use a smaller round-head dumbbell marked 12 KG. The header's upright 20 KG plate has matching labels on opposing sides of its visible face. These revisions were made with the built-in image generation tool, then resampled to the same upload dimensions. The original prompts above describe the first versions; the final editing prompts follow.

### Header correction

```text
Targeted realism correction to this header. Preserve all text exactly, including "We Go Jim" and "We're all going to make it"; preserve the background, color palette, composition and aspect ratio.

Make the dumbbell a modest real 12 kg fixed gym dumbbell, NOT 20 kg. Two smooth round compact rubber-coated steel heads with equal dimensions, subtly rounded edges and fine matte texture, a normal straight chrome knurled grip. Weight label "12 KG" in small simple gray print on the visible outer end. Head diameter should be about one third of the diameter of the standing 20 kg Olympic plate. The whole dumbbell should be about two thirds of the standing plate diameter in length. Place at almost the SAME camera depth as the standing plate so this believable real-world size comparison is unambiguous. Keep clear of the text. No stone-like cracks or random deep grooves. Subtle natural scuffs only.

The TWO larger black plates are ordinary 20 kg rubber Olympic bumper plates. BOTH use the SAME consistent real manufactured design and each exposed face has TWO matching weight labels "20 KG" positioned diametrically opposite, at the 9 o'clock and 3 o'clock sides of the center hole. Four plate labels total across the two visible plates. The far-side marking on the flat plate must be shown in correct perspective and orientation as part of the plate face. Normal 50 mm centered metal sleeves, smooth unbroken outer circumference, a single recessed circular inner ring, realistic 450 mm diameter proportions. Print labels a readable neutral gray rather than giant embossed lettering. No brand names. Authentic product-photography realism, restrained blue edge reflections, solid contact shadows. Preserve full-bleed 2.333:1 layout.
```

### Search correction

```text
Edit Image 1, the search-result artwork. Image 2 is the corrected header and the reference for gym equipment only.
Change ONLY the dumbbell at the bottom of Image 1. Match the smaller, conventional 12 KG round-head dumbbell in Image 2, with a compact pair of smooth black cylindrical rubber-coated steel heads and a normal straight chrome knurled grip. Print "12 KG" subtly and correctly on its visible outer end, replacing "20". Real manufactured gym equipment with fine matte finish, understated everyday scuffing, soft blue edge reflections, correct geometry and floor contact. Keep the dumbbell subordinate to the app; reduce its overall size about 15 percent relative to Image 1 and keep its location. No plate, stone, polygonal shape or other new object.
Preserve EVERYTHING ELSE in Image 1 exactly: app screen and all its text/numbers, device frame, every marketing text line ("We Go Jim", "Plan.", "Lift.", "Progress.", "Workout tracking."), font sizes, positions, blue lighting and navy background. Do not introduce the header tagline into this image. Maintain 3:2 landscape for 1920 x 1280 export, opaque.
```
