# Paired online Match Save: source only, NOT deployed

Final V0.8.5.1 clients use save capability **3** and paired local file format **2**. Protocol 1 and gameplay compatibility 7.7 are unchanged. Both current clients and a capable relay are required for online Save/Load. Older peers/servers retain compatible normal gameplay with a clear unsupported-save message.

## Files for the later authorized production upgrade

Upload together from `service/` after review:

- `cardlink_service.py`: authenticated room capability endpoint and version-3 per-peer advertisement.
- `battle_protocol.py`: state-message validation dispatch introduced in the first pass.
- `online_state_protocol.py`: strict public-only metadata and transaction schemas; no private capsule transport.
- `save_state_route.py`: bounded ephemeral role/epoch/transaction-order guards.

Keep the installed dependencies compatible with current `relay_protocol.py`, `table_protocol.py`, `appearance_protocol.py` and `update_manifest.py`. Do not replace an operator's manifest JSON, environment, certificates or keys. Run the complete service tests, including `test_online_state.py` and `test_save_route.py`. Python 3.11+ standard library only.

## Future operator checklist (NOT executed)

1. Verify the actual service directory and unit from existing deployment configuration. `/opt/cardlink` and `cardlink.service` are examples, not verified installed paths.
2. Arrange downtime and finish active matches. Back up the coherent Python set with permissions; record newly introduced patch files for rollback.
3. Stage the reviewed implementation and full test/dependency set. Do not upload client saves, cards, private keys, manifest JSON or environment secrets.
4. Run `python3 -B -m unittest discover -s . -p 'test_*.py'`. Review failures before installing.
5. Install the coherent reviewed files in the verified directory. Preserve systemd/TLS/environment/manifest settings. Restart only the verified service when separately authorized.
6. Verify service health and trusted HTTPS without bypasses. Updated room responses must advertise `save_state_version: 3` and both authenticated participants must advertise 3. Health alone does not prove Match Save support.
7. Human-test host and guest Save requests, accept/decline, both local lists, disconnect/new room, original decks/roles, paired Load and privacy.
8. On failure restore the coherent backed-up Python set, removing only recorded newly introduced patch files if necessary. Preserve client save files and keys. Restart only the verified unit.

## Privacy and limits

No server save database/directory is added. Only bounded capability and transaction ID/epoch/phase metadata remain in memory. Public checkpoints are validated and forwarded, not stored or logged. Each installation encrypts its own authorized private state locally; no private save capsules travel to peer or relay. Existing 524288-byte frame/rate limits and 262144-byte local capsule limit remain.

Direct/LAN uses optional reserved hello join-key offer `53533303` on unkeyed connections and a version-3 ready acknowledgement only for capable peers. This is capability negotiation, not authentication. Required room keys are unchanged. Room sessions use the authenticated capability endpoint; unsupported clients receive no save transactions.

Detected write failures cancel and clean the current transaction's staged/committed files, preserving older saves. A process/power loss during final acknowledgement can leave an orphan record or hidden pending file; Load always requires both matching records and never reconstructs a missing private half. Same original roles, installations/private keys and compatible source decks remain required. Older experimental host-envelope saves are not migrated. Custom-table online Save/Load is unsupported.

Production VM, TLS, live updater manifest, publication and retirement policy are untouched.
