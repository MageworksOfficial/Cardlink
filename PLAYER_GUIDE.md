# CardLink player guide
## Start a table
Choose Online Mode or Offline Mode on the title screen. Offline Playtest lets you control both seats. Settings includes card backs, display, key bindings, optional integrations, and About/Beta information.

Host or Join, load both decks, then press **Start Match** immediately. Missing artwork uses placeholders. Either player can choose **SYNC MISSING CARDS** while playing; verified images appear in place. Only the selected decks’ definitions and referenced face images are shared automatically. Hidden-zone inspection still has its separate permission flow.

If the connection drops during sync, validated downloads are kept and unfinished buffers are discarded. Reconnect restores gameplay separately and resumes only missing assets. Cancel Sync stops asset transfer without ending the match. Retry Missing retries incomplete cards. Advanced Network Tools retains detailed diagnostics and recovery controls.

## Bring your cards
Use the Card Library importer for PNG/JPEG/WebP images; crop/fit to gameplay size. Deck Builder adds existing card definitions with quantities and one or more leaders. Save the deck, then load it to your table. ZIP deck import scans nested folders, previews duplicate/art changes and creates or updates a deck. Confirm only after reviewing the preview.

Optional Integrations → Scryfall enables search and printing selection. Imports remain local. Decklist import accepts supported plain/Arena text; inspect unresolved rows and sections. For large lists, explicitly update the local metadata catalog first. Offline metadata does not include every printing or artwork file.

## Move and inspect
Left drag moves objects; drag empty battlefield to select a group. Right click opens actions. Double click a normal card taps/untaps with current defaults; token double click opens properties. Mouse wheel zooms, middle drag pans, arrow keys pan and Shift speeds pan. Reset View restores the camera. Menu → Controls shows current remapped bindings.

Default shortcuts include D draw, S shuffle, F discard selected local-hand card, L layout editing, Q tap, V Offline perspective, and X show/hide hands. Shortcuts pause while typing or using modal panels. Use Settings → Key Bindings for the authoritative current map.

## Hidden information and libraries
Your own hand stays visible to you. Right click a hand card to toggle public reveal; an eye means the opponent can currently see it. Reveal follows zone moves; shuffle hides cards in that library. Opponent inspection uses the request/approval flow and does not permanently reveal the whole hand. Unrestricted library search shuffles afterward; Reveal Top N and manual Scry preserve intended ordering.

Right click → Change Face cycles multi-face cards without making another instance. Hidden cards continue showing backs. Use card/library actions for top/bottom/indexed insertion and zones.

## Table tools and saves
Right click empty space to create tokens or movable counters. Menu provides life, dice, calculator, history, manual End Turn, layout and match tools. Tokens leaving the battlefield are removed. End Turn does not apply game rules.

Save/load matches through Match controls; recovery is local. Back up your user data before testing new builds. Keep private saves and libraries out of public bug reports.

## Trouble?
Keep the Windows EXE/PCK together. For connection trouble, check matching versions, service reachability and firewall permission for the outbound service ports; never bypass TLS errors. Consult KNOWN_ISSUES.md and report safe details using FEEDBACK.md.
