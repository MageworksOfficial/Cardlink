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
