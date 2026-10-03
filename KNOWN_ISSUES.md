## V0.8.5.1 updater deployment limits

- Source-only. The planned update endpoint failed live TLS verification (expired certificate); its new handler is prepared, not deployed. Verification must remain enabled.
- No matching V0.8.5.1 download package has been published in the supplied historical v7.8.1_beta release. The staged manifest intentionally has empty assets; Update Now cannot offer an older binary as the new version.
- Downloads open GitHub in the browser; installation and checking the expected checksum are manual. No automatic replacement/rollback or new app export.
- Update configuration is independent of gameplay selection, but temporary shared-host/listener deployment still shares infrastructure outages. A dedicated stable hostname/front end is a future operator migration, not an implemented server directory.

## V0.8.5 Arrange Selected acceptance limits

- Source-only V0.8.5. Existing Windows/Mac V0.8.4 exports remain intact. Native Mac and distant two-PC/public-relay acceptance for Arrange remain pending.
- Arrange excludes hand/pile and graveyard/exile/leader cards, backgrounds, boards and structural zones. Unsupported mixed selections disable the whole operation with an explanation.
- Online batches are limited to 200 selected objects and the existing normalized position range. Oversized results are refused before moving any object. Offline long rows/columns extend beyond the table at normal object size.
- Distribution keeps the outermost center positions and may retain overlap when that span is tight; use Spread Out for a readable row. Arrange does not avoid unrelated cards/zones or restore an old formation.
- Existing movement synchronization is used; no new multiplayer Undo or concurrent-edit arbitration is added. No per-object history spam is added; a concise local status reports the result.
- **NO LIVE SERVER UPDATE REQUIRED for Arrange.** This does not remove the separate, still-pending V0.8.4 appearance relay deployment requirement.

## V0.8.4 appearance scope

- Source-only; Windows/Mac exports, distant public-relay acceptance and native Mac acceptance remain pending. Matching updated clients and the separate relay patch are required.
- Save With Deck is available only when a target resolves to one existing saved-deck source. Mixed custom piles must use This Match Only. Older custom-pile cards played before source tagging cannot always be associated with their original sleeve source.
- Source images are limited to 4096×4096 and 8 MB; visual transforms can be much larger. Missing assets use fallback color. Rotation uses the image's top-left origin; there is no dedicated rotation handle (use numeric rotation).
- Background synchronization is host-sequenced for concurrent cosmetic edits; this is not gameplay authority. Conflicting simultaneous background edits may replace one another. A periodic public appearance snapshot repairs presentation differences.
- Image import Cancel can leave an unused, harmless content-addressed image. No cleanup/deletion of shared assets is performed.

## V0.8.3 Battle Feedback — current acceptance limits

- Source update only. Existing Windows/Mac downloads are unchanged. Matching V0.8.3 clients and the prepared relay validator update are required for the new online messages. The package is local; public relay deployment, distant two-computer rematch acceptance and native Mac testing remain pending.
- An interrupted reset after preparation deliberately pauses play and requires authenticated reconnect plus renewed bilateral approval. It never guesses whether the partially completed game should continue. Closing the app is not a durable online reconnect; existing in-process recovery limits remain.
- Starting recipes are captured from deck loads and saved locally with new match saves. Older/manual matches without recipes reset empty with a warning. Removed custom components are not recreated. Deck definitions/images must still be readable before reset; missing source cards block it safely.
- Loyalty is bounded to 0–1,000,000; zero remains attached. No automatic game rules. Bottom milling acts on the standard player library; independent custom piles keep their existing context operations.
- Custom deck-back PNGs are 500×700, at most 2 MB, verified by SHA-256; absent images use saved color. Online backs deliberately reveal their cosmetic deck association, like physical sleeves, without hidden card IDs/order. Legacy decks without a saved back retain local global-back behavior until configured. Template-specific back overrides remain only for piles without saved deck backs.
- Back selection occurs in Deck Builder and applies on the next deck load; no new in-match back editor. Current matches/rematches preserve the selected configuration. Importing a custom image and then canceling the picker can leave an unused hash-named asset, but does not change the deck.
- Headless tests in the restricted Windows runner emitted the existing certificate-store startup diagnostic; no TLS bypass was used. The isolated live Scryfall run passed all seven checks with normal TLS verification.

## V0.8.2 local workflow update

- Source update only; Windows/Mac exports and public releases were not replaced. Existing remote/custom relay deployment and distant acceptance limits below remain.
- Live Scryfall Red / Creature / MV 3–6 search and single-printing import passed in an isolated profile. Online filtering requires the optional provider; offline metadata retains name-only lookup. Known Sets uses the metadata loaded when the search window is created; reopen the application to refresh that picker after a catalog update, or type a set code directly.
- Collection events cover application writes, not arbitrary edits made outside CardLink. Existing Refresh remains available for external changes. Import results remain subject to current local search/tag filters.
- The filter area scrolls in compact windows. Advanced filters are collapsed initially. Full third-party artwork is not bundled or downloaded merely by changing filters.

## Builder UI/UX polish — review notes

- Build/Play uses the same Layout state. The drawer scrolls on smaller windows; corner resize handles are available for unrotated zones, shared areas, hands, leader areas and boards. Rotated objects use numeric properties. Snapping is a simple 20-unit grid plus nearby edges/centers, not a precision design suite.
- Token Quick Add opens the existing token editor; drag the finished token into place. Other-player component copies appear nearby rather than attempting automatic mirroring.
- My Tables protects built-in Standard; start Standard from the existing New Match/table selector. Template deletion does not delete cards or shared image assets. Templates remain layouts, not match saves.
- Primary Draw uses an existing validated pile link, with no new network schema. D and S use explicit personal/shared assignments, then a single owned fallback. Ambiguous sources require assignment; direct right-click Shuffle targets its pile.
- The unsaved-layout star tracks the component document. Native token/counter values are captured when opening Save Table; their independent edits do not continuously update that star.
- No new export or public server deployment. Previous custom-table relay deployment and distant two-computer/recovery acceptance limitations remain. The current tests verify local clients only.

## Custom Table Builder Foundation — current limits

- Source implementation only: existing Windows/Mac exports are unchanged. Both clients must run this updated source/build for custom tables. Old clients do not understand the new custom messages; there is no custom-capability negotiation yet.
- The local relay validator update is prepared, not deployed. Public custom-table relay acceptance, distant two-PC testing and custom reconnect/recovery acceptance remain pending. Do not assume existing live relay supports these frames.
- Multiple Hand components for one player refer to the same existing private hand. They are not additional independent hands. D and S now target the active player’s custom Primary Draw source, independently of perspective.
- Shared-pile order is held by its custodian (host for table-owned piles); individual draws use acknowledged private transfer. Ownership changes for occupied online piles are blocked. Simultaneous structural edits use the last accepted edit, without merge/conflict UI.
- Local custom piles display a revealed top face; remote custom piles currently receive counts and backs, not a separately synchronized revealed-top face. Standard library reveal behavior is preserved.
- Templates contain arrangements and text token/counter defaults, not card definitions, decks, private orders or token art. Match saves retain game objects/art. Loading a template preserves existing objects: matching unchanged defaults are reused, but moved/edited defaults may result in additional objects. Start blank for an exact fresh template.
- Optional board/back image packaging starts OFF. Missing images show placeholders. Images are bounded to 4096×4096 and 8 MB each; template packages to 16 MB and 128 components/default objects. A failed multi-image import may leave an unused verified image file, but does not commit the invalid template.
- Custom zones/areas/hands/unrotated boards now have corner handles. Rotated components use numeric size controls. My Tables manages local templates; no community browser, 3–4 player networking or automated game rules are included.

# Known limitations
- Beta status: usability and platform acceptance remain ongoing; there is no automatic rules engine or anti-cheat guarantee.
- Native macOS execution still needs testing. Universal export setup exists; ad-hoc builds are not notarized and Gatekeeper may request approval.
- Public multi-face play requires the 7.7 relay validator update. Its live deployment and a distant two-player multi-face acceptance session have not been verified in this preparation.
- Community-scale relay stress testing and long-term availability are not established. Restrictive networks may block ports 8787/8788.
- RAR deck archives are deferred; ZIP is supported.
- Optional Scryfall decklist resolution has a bounded online lookup budget; larger lists should use the explicit local metadata catalog update. Catalog contains one representative printing per card; uncached artwork needs the network.
- Decklist imports create new decks; a dedicated sideboard editor and decklist existing-deck diff are deferred. Extra sections remain metadata.
- No community server browser, automatic fallback, matchmaking, four-player mode or mobile release is implemented.
- Public project URL, private security reporting and artwork redistribution review are still publication prerequisites.
