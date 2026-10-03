# V0.8.4 — Table Appearance & Quick Controls

Source update; new Windows/Mac exports and public deployment have not been performed.

## Change a deck sleeve during play

Right-click a Standard library or Build Your Own deck/pile → **Change Deck Back**. Ctrl+F also finds Change Deck Back using sleeve, card back, deck sleeve, or back cover. When several targets exist, select the intended library/pile.

Preview the existing default, color, custom color, or custom image options. Continue to choose **This Match Only** or **Save With Deck**, then Apply. Cancel leaves the previous sleeve active. Save With Deck requires exactly one identifiable saved deck loaded into that target; it preserves the saved deck's other current fields. Mixed or missing saved sources must use This Match Only.

Online, another player's sleeve change is a request with Accept/Decline and can affect only the match. It never updates their saved deck. Colors send configuration; selected custom images use the existing bounded, hashed back transfer. Missing images use the saved fallback color.

## Quick Reset Match

**Ctrl+Alt+Shift+R** opens the existing Reset Match confirmation. It never resets immediately. Online, the opponent must still approve. Typing/modal input guards apply.

## Battlefield background

Open **Menu → Table → Battlefield Background**, right-click empty table, or use Ctrl+F (background, playmat, board, floor image).

Choose CardLink Default, a solid preset, a custom color, or a local PNG/JPEG/WebP. Custom color previews in the swatch before **Apply Custom Color**. Images use the existing managed Board Image store: 8 MB maximum, at most 4096×4096 source pixels, validated decoding, normalized PNG, and SHA-256. No permanent source-file path is retained; source image content is not cropped.

The background is one global bottom layer in Standard and Build Your Own. Board / Floor Images remain optional independent objects above it.

Enable Layout/Build Mode, then **Ctrl+B** or the Layout **Background Edit** toggle. Outside Layout Mode, Ctrl+B explains that Layout must be enabled. Unlock to drag or resize using corners, or enter position/size/rotation numerically. Resize preserves aspect ratio. Opacity ranges from 0–100%. Visual size can exceed the table, up to 20,000 units on either axis.

Fit contains the full image; Fill covers the table. Reset Transform keeps the image and restores origin, table size, zero rotation and full opacity. Reset to CardLink Default removes the custom selection. Lock prevents move/resize/rotation. Play Mode disables editing/handles while retaining the visual transform.

Backgrounds persist in match saves and custom table templates. Optional template image packaging remains OFF by default. Missing images show a fallback color. Online configuration and selected images synchronize without blocking ordinary gameplay; a small syncing status appears during transfer.

## Deployment and acceptance

Both clients need the updated source/build. A separate V0.8.4 relay validator package is required; see SERVER_V084_UPDATE.md. It is prepared, not deployed. Protocol remains 1, compatibility 7.7, and existing save versions remain unchanged. Do not mix older clients for these new messages.

Review screenshots, test logs, server ZIP and report copies are under the external MILESTONE\V0.8.4 folder. No tutorial PDF was regenerated.
