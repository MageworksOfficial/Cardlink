## Arrange Selected — V0.8.5

Select several battlefield objects with Ctrl/Shift-click or an empty-field selection box. Right-click one selected object → **Arrange**, or **Ctrl+F → Arrange Selected**.

- **Stack:** compact pile with small diagonal offsets; the existing top object stays on top.
- **Fan:** straight horizontal overlap, without a curve or rotation.
- **Line Up Horizontally / Vertically:** readable row or column, using actual object sizes and a gap.
- **Distribute Evenly:** space centers between the outermost objects on the dominant axis; ties use horizontal. The other axis is unchanged.
- **Spread Out:** a readable horizontal row, not restoration of an earlier layout.

Arrangements keep the group's approximate center, shifting inside the table when possible. Selection stays active, so you can arrange again or drag the group. Tapped cards stay tapped. Normal cards, tokens and standalone counters remain independent. Hand/pile cards, graveyard/exile/leader cards and table structures cannot be arranged; remove unsupported items from a mixed selection first. Local Undo restores one arrangement; online Undo remains disabled. Online arrangements allow up to 200 selected objects and reject results beyond existing network position limits.

## CardLink 7 V0.8.4 Beta — Table Appearance & Quick Controls

In-match deck sleeves (match-only or saved), safe **Ctrl+Alt+Shift+R** Reset Match, and shared battlefield backgrounds with **Ctrl+B** guarded transform editing are implemented in local source. See [TUTORIAL_V084_CHANGES.md](TUTORIAL_V084_CHANGES.md) and [CARDLINK_7_V084_APPEARANCE_REPORT.md](CARDLINK_7_V084_APPEARANCE_REPORT.md). Updated clients and the prepared relay patch are required online; no export or live deployment was performed.

## Hand groups, library placement, and Surveil

- Ctrl-click hand cards, release Ctrl, then drag a selected card onto the battlefield to play the selected hand cards in a spaced row. Detached hands work too. Selected battlefield objects are not included in a hand drop.
- Ctrl+D places one top card beside the library. D still draws to hand. On custom tables, Ctrl+D uses the active player's Primary Draw source, with the same ambiguity guards as drawing.
- Library Actions → Top N → Battlefield uses the number field. In library inspection, select a card and choose Battlefield; it appears beside the library. Unrestricted search still shuffles when closed.
- Hand or Library Actions → Enter battlefield face down controls hand drops and library placement. The inspection window also offers this option. This is a session preference, initially off. Turn it off for face-up placement.
- Library Actions → Surveil N opens the top N cards. Move chosen cards to the graveyard list, reorder kept cards, then confirm. Cancel changes nothing; a changed library or full graveyard prevents confirmation. Surveil does not shuffle.
- Online private libraries remain controlled by their holder. A face-down transfer from an opponent's inspection must be performed by that player; it is never silently played face up.

## Selecting several cards and objects

Ctrl-click (or Shift-click) adds/removes battlefield cards, tokens, counters and cards in your currently displayed hand. You can combine hand and battlefield cards in one selection. Gold outlines identify selected cards. Right-click any selected member to open mass actions; the menu stays at readable screen size when zooming and works from the detached hand too. Plain click on an unselected object selects it alone; clicking empty battlefield clears the selection. Field group dragging moves field objects; selected hand cards can be dragged together to play them; release Ctrl before dragging. Bulk actions use the existing owner/zone and token lifecycle rules, never delete card definitions.

## Find cards and functions — Ctrl+F

Press **Ctrl+F** during offline or online play to find a function by name: Search Library, Search Hand, tokens, counters, dice, save, Reset Match and more. Select a result and press Enter (or double-click); Escape closes the panel. It is also available under **Menu → Search / Functions**. Library searches retain their normal shuffle-on-close behavior and online opponent-access permission checks. No hidden card names are indexed by this panel.

In Card Collection, Deck Builder, an open inspection or Online Card Search, Ctrl+F focuses that screen’s existing search box. In Build Your Own, find **Search Table Components** to focus the builder search. Confirmation/import windows remain protected. Optional Scryfall search still needs internet even during Offline Playtest; local collection/hand/library search does not.

## V0.8.3 — Battle Feedback

- Open **Deck Builder** directly from the title screen. Create/edit/save, import custom cards, use optional Scryfall search/decklists or ZIP import, then **Back to Title**. No match is created. The existing unsaved-deck confirmation still applies.
- Use **Deck Back…** in Deck Builder. Choose CardLink Default, one of ten colors, click the Custom Color swatch for the native RGB/HSV/hex picker, or choose an image. **Use for this deck**, then **Save / Rename**. Images are center-filled to 500×700 and stored by hash, with a 2 MB limit. Missing images fall back to the saved color. Previously saved decks with no back field retain the old local preference until a back is selected.
- Host/Join remembers the nickname used on a successful connection. **Settings** can change it during a match; the connected opponent receives the new label. It is not an account or credential.
- Card actions → **Counters → Loyalty…** provides −1, +1, direct entry, Add/Set and Remove. Zero stays visible; negative input clamps to zero. Zero never destroys the card. Loyalty uses the existing public attached-counter system and saves with the match.
- Library actions → **Mill N from Bottom** uses the same N input as Mill N. For A B C D E (top to bottom), milling two appends D then E to the graveyard's ordered list. Oversized requests move all remaining cards; empty libraries do nothing. Online, the player holding the private library performs this action. Only the milled cards and resulting count become public.
- **Menu → Match → Reset Match…** is a full rematch, separate from Reset View/Layout. Confirm locally, or request online and have the opponent Accept. Decline leaves the game intact. Both players keep their connection, names, decks, backs, downloaded assets and table structure. Hands, public cards, temporary tokens/counters, graveyard/exile, life, turn, history and inspection grants reset. Libraries are rebuilt from the deck recipes recorded when loaded, then shuffled; the current order is never the source.
- Build Your Own keeps components, positions, board art and template. Loaded pile recipes return to their original composition. Manually populated piles without a recorded deck become empty. Older/manual saves without a starting recipe warn that reset will leave an empty table. No collection/deck files are deleted.
- If a connection drops before preparation, the request cancels. If reset preparation/commit is interrupted, a **Reset paused** window protects both clients. Reconnect on both computers, then Request Reset Again and accept again. Do not start a separate room or manually continue different game states.

Both clients and a public relay must have the V0.8.3 update for online rematches/back sharing. See SERVER_V083_UPDATE.md. No live deployment or updated app export was performed here.

# Build Your Own — CardLink 7 V0.8.2 Beta

Choose **Build Your Own** after Online/Offline. Start blank, or choose **Simple Table** (two decks, two hands and a shared area) or **Shared Deck Table**. These are editable arrangements, not game rules.

## Build and play

**L** switches between **BUILD MODE** and **PLAY MODE**, using the existing Layout system. In Build Mode, open **Table Builder**, or use **Ctrl+F → Search Table Components** to focus its component search. Search finds component types, not cards; try library, grave, shared or board. The optional **Toggle Table Builder** action can be assigned in Key Bindings; it starts unbound so your gameplay shortcuts are unchanged.

Choose a Quick Add item, move its translucent preview, and click the field to place it. Escape cancels. Tokens open their familiar editor and can then be dragged into place. The drawer collapses to make room for placement.

Click a component to select it. Drag to move; cyan guides help align to the grid, other objects or table center. Use corner handles to resize zones, shared areas, hands, leader areas and unrotated boards. Rotated objects retain numeric size controls under **More / Resize**. A locked component must be explicitly unlocked to drag or resize. Boards start locked.

The selected-object controls offer name (Enter to rename), owner, lock, hide, duplicate, other-player copy and removal. Duplication copies structure only, never pile contents. Other-player copies appear nearby for manual positioning. Hidden objects stay in **ON TABLE** with a visibility checkbox. Lock/Unlock All is available in the drawer.

**P1**, **P2** and **SHARED** badges use subtle blue, lavender and cyan accents. Areas have transparent fills so cards remain dominant. Play Mode collapses the drawer and removes handles and guides; card play stays available. Reopen the drawer to return to Build Mode.

## Drawing and perspective

Use a pile's right-click **Set as Primary Draw Pile** / **Use as Shared Draw Source**, or the selected-object button. **DRAW** / **SHARED DRAW** marks the effective source. D and S first use an explicit personal primary, then an explicit Shared Draw source, then a single owned pile. If several owned piles remain unassigned, neither shortcut guesses: right-click the desired pile and set its assignment. Hiding a pile changes its display, not its assignment.

- **D** draws for the active player from their custom draw source.
- **N** ends the turn and changes active player, without applying game rules.
- **V** changes the viewed side only. A separate Viewing / TURN indicator explains when view and turn differ.
- A Shared Deck routes its draw to the active player's hand. Per-player primary choices take priority; choosing Shared Draw clears existing explicit personal designations.
- **S** shuffles the active player’s custom draw source. Right-click any pile → **Shuffle** shuffles exactly that pile, regardless of turn. No source produces a short status message. Standard tables keep their existing shuffle behavior.

Nonempty hands appear automatically after drawing, even without a Hand component. Add Hand components to keep empty hands visible or deliberately hide a seat’s hand through component visibility. X remains the global hide/show control. Multiple Hand components for one seat still refer to that same hand. Load saved decks through each selected pile's **Load Saved Deck** control. Removing an occupied component offers Return to Battlefield, Move to Another Pile, or Cancel. Online, the player holding a private pile must handle its occupied removal; unsupported remote relocation is disabled.

## My Tables

**Save Table** asks for name, description and optional author. You can export after saving. Saving an existing ID offers **Update** or **Save Copy**. The table name gains an asterisk when component-layout changes are unsaved.

**My Tables** shows each template's name, description, author and component count. Load, edit details, duplicate, export or delete saved templates. Deletion asks first and leaves match cards and image assets intact. CardLink Standard is protected and remains available through the normal New Match / table selection flow.

`.cltemplate` exports contain layout and token/counter defaults, not your card collection or private pile order. Including board/back images is optional and starts OFF. Review imports before confirming. Missing images can be replaced in Board properties. Only redistribute art you have permission to share.

Loading an arrangement returns existing pile cards to the battlefield and preserves existing objects. Use **Match Save/Load** to preserve an ongoing game. Unchanged matching token/counter defaults are reused; moved or edited defaults can create additional objects when loading into a nonblank table.

Both clients must have custom-table support for online editing. The existing relay update still requires operator deployment and distant acceptance. This polish pass does not change the networking architecture. See KNOWN_ISSUES.md and CARDLINK_7_V081_BUILDER_UX_REPORT.md.

# CardLink player guide
## Start a table
Choose Online Mode or Offline Mode, then **CardLink Standard** or **Build Your Own**. Standard retains the familiar deck setup; Build Your Own opens a blank table. Offline Playtest lets you control both seats. Settings includes card backs, display, key bindings, optional integrations, and About/Beta information.

For CardLink Standard, Host or Join, load both decks, then press **Start Match** immediately. Missing artwork uses placeholders. Either player can choose **SYNC MISSING CARDS** while playing; verified images appear in place. Only the selected decks’ definitions and referenced face images are shared automatically. Hidden-zone inspection still has its separate permission flow.

If the connection drops during sync, validated downloads are kept and unfinished buffers are discarded. Reconnect restores gameplay separately and resumes only missing assets. Cancel Sync stops asset transfer without ending the match. Retry Missing retries incomplete cards. Advanced Network Tools retains detailed diagnostics and recovery controls.

## Bring your cards

- **Card Library → + Add Custom Card** imports an image from your computer. In **Deck Builder**, use **+ Import Custom Card** to open the same importer without leaving your deck.
- Choose Image, adjust the locked 5:7 crop with Fit/Fill/Reset, zoom and pan, enter a name, then confirm. Add Another Face stays available. Success offers **Add to Current Deck** when opened from Deck Builder, or **View Card** from Card Library; **Done** closes the importer.
- **Online Card Search** opens optional Scryfall search. Enable it explicitly in Integrations. Name (including existing raw query syntax), colors, card type, mana value minimum/maximum, format, set code and rarity narrow a search. Checked colors match any checked color. **Known Sets** uses already-downloaded metadata; no catalog download is needed for name search or a typed set code.
- **Advanced Filters** adds commander identity (WUBRG letters, or C alone for colorless), oracle text, artist, collector number and sort. Identity means colors contained within that identity. Either mana bound may be blank; invalid or reversed ranges are rejected. Configure filters, then press **Search**. **Clear Filters** keeps the name and returns to simple name search. Local metadata search is name-only; filtered queries require the optional online provider.
- Search → select card → Choose Printing → Add to Library. Only visible previews load while browsing; full faces download on import. If opened from Deck Builder, **Add to Current Deck** adds the definition using normal quantity behavior. You can add another copy with the same button.
- **Import Decklist** builds a saved deck from a pasted plain/Arena list. Review unresolved rows and sections before importing. Large lists can use the explicitly downloaded local metadata catalog. A new saved deck does not replace your unsaved working deck.
- **Import ZIP Deck** scans nested PNG/JPEG/WebP images and previews duplicates/art changes before creating or updating a saved deck. Review the preview before confirming. RAR remains deferred.

Custom, online, decklist and ZIP imports update Card Library and Deck Builder automatically. No Save → Close → Reopen step is needed. Current deck fields, quantities, leaders, selection and available-list scroll are preserved. A newly imported card must still match your current library search/tag filters to appear. Clear those filters if needed. An empty Card Library explains both custom and online entry points.

## Move and inspect
Left drag moves objects; drag empty battlefield to select a group. Right click opens actions. Double click a normal card taps/untaps with current defaults; token double click opens properties. Mouse wheel zooms, middle drag pans, arrow keys pan and Shift speeds pan. Reset View restores the camera. Menu → Controls shows current remapped bindings.

Default shortcuts include D draw, S shuffle, F discard selected local-hand card, L layout editing, Q tap, V Offline perspective, and X show/hide hands. Shortcuts pause while typing or using modal panels. Use Settings → Key Bindings for the authoritative current map.

## Hidden information and libraries
Your own hand stays visible to you. Use a hand card’s right-click Reveal/Hide action; an eye means the opponent can currently see it. Reveal follows zone moves; shuffle hides cards in that library. Opponent inspection uses the request/approval flow and does not permanently reveal the whole hand. Unrestricted library search shuffles afterward; Reveal Top N and manual Scry preserve intended ordering.

Right click → Change Face cycles multi-face cards without making another instance. Hidden cards continue showing backs. Use card/library actions for top/bottom/indexed insertion and zones.

## Table tools and saves
Right click empty space to create tokens or movable counters. Menu provides life, dice, calculator, history, manual End Turn, layout and match tools. Tokens leaving the battlefield are removed. End Turn does not apply game rules.

Save/load matches through Match controls; recovery is local. Back up your user data before testing new builds. Keep private saves and libraries out of public bug reports.

## Trouble?
Keep the Windows EXE/PCK together. For connection trouble, check matching versions, service reachability and firewall permission for the outbound service ports; never bypass TLS errors. Consult KNOWN_ISSUES.md and report safe details using FEEDBACK.md.


## Saving an online match (standard tables)

Either player can request Save Match. The other player must ACCEPT or DECLINE. After both writes succeed, both see Match Saved and both Load Match lists contain the checkpoint. Reusing a name creates a separate save; its internal ID identifies the pair.

To return later, reconnect on the original installations in the original Host/Guest roles, load compatible original decks and finish Card Sync. A new room code is fine. The host chooses Load Match; the guest approves the matching local record. Both must retain their own saves and local private keys. Saves contain game state, not a portable source deck or image package. Missing paired records or changed decks block restore. Updated clients and a capable room server are required. Earlier experimental saves and custom-table online saves are unsupported.

Hands and X still show/hide hands; right-click Hands for detached-hand controls.
