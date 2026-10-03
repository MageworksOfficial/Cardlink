# Tutorial revision notes — V0.8.3 Battle Feedback

The existing PDF was not regenerated.

Add screenshots of: title Deck Builder button; standalone workspace and Back to Title; Deck Back picker; Loyalty dialog; Mill N from Bottom; online reset request and acceptance; Reset paused recovery window.

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

