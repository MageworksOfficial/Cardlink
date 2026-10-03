# V0.8.3 Battle Feedback relay update — NOT DEPLOYED

A LIVE RELAY UPDATE IS REQUIRED before using V0.8.3 clients through the public relay. This is an additive strict-schema extension under protocol 1 / compatibility 7.7. Both clients must be updated. Old clients cannot understand the new handshake capability fields; use matching versions.

## Exact local files

Project root: `<PROJECT_ROOT>`

Prepared folder: `SERVER_UPDATE_V083`

ZIP: `CardLink-V0.8.3-Relay-Update.zip`

Required files (keep together in the existing Linux service directory):

- `relay_protocol.py` — updated dispatcher/public-card validator, optional reset epoch, optional handshake capability/pending-reset flags.
- `battle_protocol.py` — new bounded cosmetic and reset-control validator.
- `table_protocol.py` — existing unchanged custom-table validator required by the dispatcher; supplied for completeness. Do not substitute the older 7.7-only bundle.

Verification: `test_battle.py`, `test_faces.py`, `test_table_protocol.py`, `test_service.py`; a SHA256SUMS file identifies the package files.

**Keep cardlink_service.py unchanged.** No server configuration, TLS certificate paths, authentication secrets, public address or protocol number changes are required.

## Scope/privacy

Only cosmetic back configs and required hash-named PNG chunks (2 MB maximum, 32 KiB chunks), display nicknames, reset IDs, and existing public-state projections are added. No starting-deck recipe, unrequested hidden identity, private order or private match snapshot is introduced. Existing single/multi-face, hidden-zone, transfer and recovery validators remain strict. Extra keys are rejected. Client code retains approval checks, epoch rejection, hash/dimension verification and authenticated reconnect; the relay remains a schema validator, not a rules referee.

## Later operator deployment

1. Obtain explicit deployment approval; this task has not contacted or changed the server.
2. Back up the current validator files, record the service directory and actual systemd unit name. Leave the running service code/config/certificates alone.
3. Upload the three required Python files together through the normal SSH/file-upload workflow. Upload the four test files if verification is desired. Preserve ownership/permissions.
4. From the service directory run `python3 -m unittest test_service test_faces test_table_protocol test_battle`. Local package validation: 37 tests passed.
5. Restart the existing CardLink systemd unit using its actual name. Do not guess a service name or disable TLS checks. Confirm service health and normal room create/join/relay probe.
6. Use two V0.8.3 clients: load decks with different backs, draw privately, play a card with Loyalty, mill from bottom, decline a reset, then accept a reset. Confirm the same room/connection, full shuffled libraries, cleared hands/history and retained names/backs. Repeat with a custom back image missing on the second PC.
7. Interrupt a reset during preparation; reconnect both clients, verify the pause, and approve a fresh reset. Confirm both clients resume the same new game.
8. If validation fails, restore the backed-up validators and restart the same service. Use the corresponding older clients until the complete update is installed.

No server login, upload, restart, TLS bypass, publication or app export was performed by this update. Distant public-relay acceptance remains an operator test after deployment.
