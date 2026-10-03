## CardLink 7 V0.8.5.1 Beta — Independent updater architecture

- Nonblocking startup update check, small clickable version indicator, gentle pulse respecting Reduce Motion, and fixed-action update dialog.
- Separate update.cfg, validated HTTPS metadata, four-hour cache and stale-required refresh/fail-open behavior. Online entry gates preserve offline availability.
- Prepared GET /v1/update metadata adapter, server validator/cache and tests; GitHub remains the download host. Server Directory is a placeholder only.
- No deployment, automatic installation or app export. Live certificate validation failed; matching new release packages still need publication. See UPDATING.md.

## CardLink 7 V0.8.5 Beta — Arrange Selected (2026-09-28)

- Added one screen-fixed Arrange submenu and Ctrl+F entry with six positioning choices: Stack, Fan, Horizontal, Vertical, Distribute and Spread.
- Existing selection, stacking order, independent state, group dragging, mixed gameplay objects and offline grouped Undo are preserved.
- Reused public position batches; unchanged protocol, relay and save compatibility. No server/source schema changes or deployment.
- 93 focused checks, 44 two-local-client checks, 20 existing regression suites and graphical review passed. See CARDLINK_7_V085_ARRANGE_REPORT.md.
- Final planned feature milestone complete; exports, distant acceptance, publishing and subsequent feature milestones are not performed here.

## CardLink 7 V0.8.4 Beta — Table Appearance & Quick Controls

In-match deck sleeves (match-only or saved), safe **Ctrl+Alt+Shift+R** Reset Match, and shared battlefield backgrounds with **Ctrl+B** guarded transform editing are implemented in local source. See [TUTORIAL_V084_CHANGES.md](TUTORIAL_V084_CHANGES.md) and [CARDLINK_7_V084_APPEARANCE_REPORT.md](CARDLINK_7_V084_APPEARANCE_REPORT.md). Updated clients and the prepared relay patch are required online; no export or live deployment was performed.

## CardLink 7 V0.8.3 Beta — Battle Feedback (2026-09-27)

- Bilateral same-session rematches, local starting-deck recipes, fresh match epochs and interrupted-reset recovery guard.
- Successful-connection nickname persistence and live Settings label updates.
- Loyalty convenience counter and deterministic Mill N from Bottom.
- Saved per-deck default/preset/custom-color/custom-image backs, safe cosmetic configuration and image sharing.
- Title-screen standalone Deck Builder using existing import and collection workflows.
- First Beta Tester credits: Mattamn and Picklenick99.
- Optional local save extensions preserve older file compatibility. Protocol/compatibility numbers unchanged; the new capability and strict relay schemas require updated clients/relay. Prepared locally, not deployed; no exports/publication.

## CardLink 7 V0.8.2 Beta — Card workflow / collection QoL

- Fixed stale Deck Builder available-card records using one collection-change feed shared with Card Library, including worker-thread ZIP imports, online/decklist imports, multi-face changes and metadata/delete writes.
- Preserved unsaved deck fields, quantities, leaders, selected deck/card and available-list scroll; added post-import Add to Current Deck using ordinary quantities.
- Promoted Add Custom Card / Import Custom Card beside Online Card Search, Import Decklist and Import ZIP Deck, with tooltips, empty-library guidance and the existing crop/face importer.
- Added basic and collapsible advanced Scryfall filters, validated optional mana bounds, Clear Filters, active summary and explicit Search. Existing provider queue, cache, consent and full-image import remain in use.
- Made S use D’s guarded active-player custom draw source; direct pile context Shuffle remains independent of turn. Ambiguous assignments no longer pick the first pile.
- Added focused collection/filter/pile tests and isolated live-provider acceptance. Retained protocol 1 / compatibility 7.7 / existing save formats. No server change, export replacement or publication.

## Custom-table hand visibility hotfix

- Fixed drawn cards disappearing from view when a custom table had no matching Hand component. Nonempty hands now show automatically after draws, perspective/camera changes and match restore.
- X and detached hands use the same custom presentation policy. Explicitly hidden Hand components and intentional global hiding remain respected.
- Added 20 focused checks; reproduced 12 visibility failures before the fix, then passed all 20 and 9 affected regression suites. Graphical fixture checks confirm both players' hand cards display without toggling X. Existing exports were not replaced.

## CardLink 7 V0.8.1 Beta — Custom Table Builder UI/UX polish

- Fixed D to draw from the active player's custom source independently of V perspective; N retains existing turn switching. Added Primary Draw / Shared Draw designation using existing validated links.
- Added a collapsible Table Builder, component-only search, ghost placement/cancel, selection outlines, corner resizing and simple snap guides.
- Added ownership/draw badges, Build/Play mode clarity, direct object controls, structure-only duplication, visibility/locking and safe occupied removal/relocation.
- Added editable Simple/Shared Deck recipes, My Tables metadata/copy/export/delete management, Update/Save Copy prompts and unsaved-layout status.
- Added review screenshots at 1152×648, 1920×1080 and 960×540 and focused automated tests. Standard and existing connection architecture are preserved. No publication, server deployment or new major game system.

## CardLink 7 V0.8.1 Beta — Custom Table Builder Foundation

- Added Standard / Build Your Own selection after Online/Offline, using clean existing artwork and supplied navigation crops.
- Added blank tables, searchable components, multiple independent piles, table-owned shared draws/discards, editable zones and board images.
- Added bounded data-only `.cltemplate` save/load/export/import with opt-in board/back images and token/counter defaults.
- Added custom match-save extension and custom structure/board/shared-pile messaging through existing connections and private transfer transactions.
- Added local, two-client and service validation tests. Live relay deployment and two-PC custom acceptance remain pending.
- Player-facing label changed; historical release tags, protocol 1 and 7.7 wire compatibility identifiers are not rewritten.

# Changelog
## CardLink 7.8.1 Beta — Online preparation hotfix
Host or Join, load both decks, then press **Start Match** immediately. Missing artwork uses placeholders. Either player can choose **SYNC MISSING CARDS** while playing; verified images appear in place. Only the selected decks’ definitions and referenced face images are shared automatically. Hidden-zone inspection still has its separate permission flow.
## CardLink 7.8 Beta — local public-release preparation
Beta title/About, anonymous tester credits, feedback placeholder and publication/security documentation. No gameplay or wire-version change.

## Major development phases
- Early prototype: draggable tabletop, independent instances, tap/preview and ordering.
- Collection and decks: image normalization/deduplication, card library, Deck Builder, leaders, playable libraries and hands.
- Local sandbox: freeform zones, hidden backs, manual Scry, tools, tokens/counters, history, saves and selection.
- Multiplayer: two-client identity, public actions, hidden-information boundaries, permissioned inspection, selected-deck-scoped background Card Sync and reconnect/resync.
- Public connection: verified TLS room-code service, relay and diagnostics.
- Presentation and playtest: title screen, Offline two-seat play, usability controls, configurable key bindings and display preferences.
- 7.7: multi-face definitions and instances, face-aware synchronization and validator update package.
- 7.8: optional Scryfall search/printing import, local metadata and text decklist import.
