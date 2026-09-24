# CARDLINK title-screen assets — Astra handoff

## Contents

10 reusable PNG assets plus the original reference image. UI and icon files have real PNG alpha transparency; panel and button interiors remain dark navy. The background is opaque.

| File | Purpose |
| --- | --- |
| ui/cardlink_title.png | CARDLINK metallic wordmark, circular compass, glow, and “A TABLETOP CARD SANDBOX” subtitle as one composite. |
| ui/online_mode_panel.png | Complete Online Mode selection panel: frame, world map, two players, globe, title and description. |
| ui/offline_mode_panel.png | Complete Offline Mode selection panel: frame, two players, cards, title and description. |
| ui/settings_button.png | Complete Settings button with gear and label. |
| ui/exit_button.png | Complete Exit button with door/arrow and label. |
| background/background_tabletop_reconstructed.png | Full 1672 × 941 environment with overlaid UI/text removed and concealed areas reconstructed. Side cards, foreground stacks and tabletop glow remain part of this background. |
| icons/icon_settings_gear.png | Separate gear icon for reusable controls. |
| icons/icon_exit_door.png | Separate exit icon. |
| icons/icon_player_blue.png | Separate blue player silhouette. |
| icons/icon_network_globe.png | Separate cyan wireframe network globe. |
| reference/original_title_screen.png | Unmodified supplied title screen, the visual reference for final layout. |
| manifest.json | Actual pixel dimensions, alpha-channel status and SHA-256 hashes for each reusable PNG. |
| generation_prompts.json | Prompts used with the built-in imagegen tool for provenance and later revisions. |

## Fidelity and transparency

The input was a flattened raster image, not an editable layered source. The supplied assets are AI-assisted reconstructions/extractions, not pixel-exact source crops or recovered original layers. Fine details, proportions, typography, and glow strength can differ from the reference. No original hidden background pixels can be recovered; covered areas of the background were reconstructed.

All nine UI/icon PNGs retain generated alpha, including their soft blue edges. The original dark interiors of panels/buttons and part of the title reticle remain intentionally opaque. Check their glow on the provided dark backdrop; a light backdrop will change the appearance. Transparent canvas padding varies between assets. Original generated files were preserved without postprocessing.

Text is baked into the composite title, panels, and buttons. It is not editable font text. The tiny decorative slogans/version in the original were omitted from the reconstructed background; use live labels if these are desired. Side display cards and foreground stacks stay within the environment because they are blurred, overlapping scenery rather than clean standalone UI.

## Layout guide

Reference viewport: 1672 × 941. Approximate ORIGINAL visible artwork rectangles below use top-left x/y and width/height, in reference pixels. They describe intended placement, not crop coordinates in the generated PNGs, and exclude most outer glow. Account for each generated texture's transparent padding when matching these regions.

| Element | x | y | width | height |
| --- | ---: | ---: | ---: | ---: |
| Main title area (including compass and subtitle) | 410 | 12 | 844 | 340 |
| Online panel | 309 | 363 | 510 | 286 |
| Offline panel | 853 | 363 | 511 | 286 |
| Settings button | 550 | 684 | 268 | 64 |
| Exit button | 853 | 684 | 267 | 64 |

Match the two panel frames to equal display sizes and match the two small buttons to equal display sizes. Generated canvases and border proportions vary, so simply setting all textures to native size will not reproduce the original screen. Preserve aspect ratio where possible and compare against the original. Use the supplied pixels as texture assets, not screen-size recommendations.

## Godot handoff

- Copy background/, ui/ and icons/ into the project's asset folder.
- Place the background behind a responsive Control layout; keep its aspect ratio and crop/letterbox intentionally.
- Display the title with a TextureRect. Use the complete panel/button textures as normal-state artwork for clickable Controls or TextureButtons.
- Fit textures to the intended visible frame bounds, accounting for transparent margins. Keep input/focus rectangles around the visible controls rather than the entire glow canvas.
- The PNGs contain artwork only. Astra must connect Online, Offline, Settings and Exit actions to existing project handlers.
- Offline Mode should open the local playtest with both player sides displayed as if connected; it must not require an actual multiplayer connection.
- Only normal-state artwork is supplied. Add hover, pressed, disabled and keyboard/controller focus behavior in Godot.
- Do not use a nine-patch to stretch the composite panels: their icons and baked text would distort. Use uniform scaling, or rebuild frames and labels separately for a more flexible future UI.
- These are not a tested Godot scene or a modification to the existing project. No project files were changed.

## Validation

Every reusable image was opened for visual inspection. UI/icon files were checked for an alpha channel and fully transparent corner pixels. The packaged PNG bytes are the generated originals, and the reference is a direct copy of the supplied image. The ZIP was checked against manifest hashes after creation.

