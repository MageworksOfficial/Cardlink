## CardLink 7 V0.8.5.1 Beta — Independent update checks

The title screen now checks a separately configured Update Service without delaying startup. Click the corner version/status area for update details; Reduce Motion disables its gentle pulse. Recent metadata is cached, and stale required-update responses cannot block online indefinitely during an outage. Offline remains available.

**Updates, future server listings, and gameplay relays are separate systems.** GitHub Releases hosts downloads; community/selected relays will not control updates. See [UPDATING.md](UPDATING.md) and [CARDLINK_7_V0851_UPDATER_REPORT.md](CARDLINK_7_V0851_UPDATER_REPORT.md). The endpoint update is prepared, not deployed; the live certificate currently fails validation. No new package is advertised until matching release assets are published. This adds checks and browser download links, not automatic installation.

## CardLink 7 V0.8.5 Beta — Arrange Selected

Multi-select battlefield cards, tokens or standalone counters, then **right-click → Arrange**: **Stack**, **Fan**, **Line Up Horizontally**, **Line Up Vertically**, **Distribute Evenly**, or **Spread Out**. **Ctrl+F → Arrange Selected** opens the same six choices. Selection stays active; each object remains independent.

Arrange is positioning only: tap/face state, ownership, counters and identities stay unchanged. It works in Standard and Build Your Own, using existing public movement online. See [CARDLINK_7_V085_ARRANGE_REPORT.md](CARDLINK_7_V085_ARRANGE_REPORT.md). This source milestone has not been exported or published. **No additional live server update is required for Arrange**; earlier V0.8.4 deployment requirements remain.

## CardLink 7 V0.8.4 Beta — Table Appearance & Quick Controls

In-match deck sleeves (match-only or saved), safe **Ctrl+Alt+Shift+R** Reset Match, and shared battlefield backgrounds with **Ctrl+B** guarded transform editing are implemented in local source. See [TUTORIAL_V084_CHANGES.md](TUTORIAL_V084_CHANGES.md) and [CARDLINK_7_V084_APPEARANCE_REPORT.md](CARDLINK_7_V084_APPEARANCE_REPORT.md). Updated clients and the prepared relay patch are required online; no export or live deployment was performed.

# CardLink

**CardLink gives you the table. The players decide what game goes on it.**

Bring your own card images, build decks, and play a manual tabletop with a friend or control both seats offline. Choose **CardLink Standard** for the familiar setup or **Build Your Own** for a blank table with independent decks, shared piles, zones, board images, tokens and counters.

Use **Build Mode** and the collapsible **Table Builder** to place, resize and organize components; switch to **Play Mode** to hide editing handles. **Ctrl+F** focuses component search. **DRAW** badges identify the pile used by D (draw) and S (shuffle) for the active player; V changes perspective only. **My Tables** manages your saved arrangements. Save your arrangement as a local template; export/import `.cltemplate` files to share the arrangement. Optional board images are excluded by default. Templates never package your card collection.

Start with [PLAYER_GUIDE.md](PLAYER_GUIDE.md). Read [KNOWN_ISSUES.md](KNOWN_ISSUES.md) before testing. This source milestone has not replaced existing downloadable builds. Custom-table online play requires both updated clients and the prepared relay validator update when using relay; deployment and distant acceptance are pending.

See [the Battle Feedback report](CARDLINK_7_V083_BATTLE_FEEDBACK_REPORT.md) for V0.8.3 validation. Historical technical version 7.8.1, wire protocol 1 and compatibility 7.7 are retained. **Online V0.8.3 requires matching clients and the prepared [relay update](SERVER_V083_UPDATE.md); it has not been deployed.**

## Shuffle up and play again

**Menu → Match → Reset Match** rebuilds the starting decks and clears the old game while keeping the table and connection. Online, both players approve. Saved nicknames, per-deck backs, Loyalty counters and **Mill N from Bottom** reduce routine setup. **Deck Builder** now opens directly from the title screen, with imports, ten back colors, a full color picker and custom images.

## Add, find and use cards

Card Library puts **+ Add Custom Card** first; Deck Builder has **+ Import Custom Card**. Both open the same crop/Fit/Fill importer. **Online Card Search**, **Import Decklist**, and **Import ZIP Deck** sit beside them with short tooltips. Imports refresh both collection views automatically while preserving your current deck edits. Successful custom/online imports from Deck Builder offer **Add to Current Deck**.

Optional Scryfall search now includes color, type, mana value, format, set and rarity filters, plus collapsible advanced filters. Set your filters, then press Search; Clear Filters returns to simple name search. Full card images still download only when you choose to import.

In Build Your Own, D and S use an explicit personal primary pile, then an explicit shared source, then a single owned pile. With several unassigned piles, assign a primary instead of guessing. Right-click → Shuffle always targets that pile. This is a local source update only, not a replacement public release.

## License

CardLink is licensed under the GNU General Public License v3.0 (GPL-3.0). You may use, study, modify and redistribute its source under the [LICENSE](LICENSE). Distributed modified versions must comply with GPL-3.0. Third-party artwork, card images, game assets, trademarks and other content are not automatically covered by CardLink's GPL license; see [THIRD_PARTY_NOTICE.md](THIRD_PARTY_NOTICE.md).
