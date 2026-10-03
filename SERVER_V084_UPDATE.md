# V0.8.4 appearance relay patch — PREPARED, NOT DEPLOYED

LIVE SERVER UPDATE REQUIRED. Use matching V0.8.4 clients. Protocol 1, compatibility 7.7, TLS verification, server endpoints, and save versions remain unchanged. Older clients do not understand the new appearance message kinds; version-number equality alone does not make mixed clients compatible.

Package: external MILESTONE/V0.8.4/server/CardLink-V0.8.4-Relay-Update.zip.

Upload these files together into the existing CardLink Linux service directory:

- relay_protocol.py (current dispatcher, supplied for a complete dependency set)
- battle_protocol.py (adds public background and sleeve-request schemas)
- table_protocol.py (optional validated template background field)
- appearance_protocol.py (strict background validation)

**Keep cardlink_service.py unchanged.** No credentials, private game data, certificates, endpoint configuration or arbitrary file paths are included.

Optional test files: test_service.py, test_faces.py, test_table_protocol.py, test_battle.py, test_appearance.py.

## Operator checklist — later, not performed by this task

1. Record the real service directory and systemd unit name. Back up the current validators, including whether appearance_protocol.py already exists. Do not guess a unit name.
2. Upload the four required files together; preserve ownership and permissions. Optionally upload the five tests.
3. Check SHA256SUMS from the uploaded package. From the existing service directory run:

   python3 -B -m unittest test_service test_faces test_table_protocol test_battle test_appearance

4. All 43 tests passed locally. If server-side validation fails, restore the previous files before restarting.
5. Restart the existing CardLink systemd unit, then verify the ordinary health, room-code create/join and relay probe with normal TLS verification.
6. Use two updated clients. Change sleeves, decline then accept the other player's sleeve request, and confirm no remote saved deck changes. Select an image absent on the second machine.
7. Change background color/image and transform from each client. While the image transfers, draw or change life and confirm gameplay stays responsive. Disconnect/reconnect and confirm background recovery.
8. Ctrl+Alt+Shift+R must open confirmation and require online acceptance; cancel/decline first. Repeat existing approved-rematch recovery checks.
9. Rollback: restore the backed-up validator set together and restart the same unit; use the matching previous clients.

## Privacy and limits

Background messages contain only type, color, image hash, numeric transform/opacity, and lock state. Sleeve requests contain only a target library/pile and validated back configuration. Extra fields are rejected. Background files use at most 8 MB, 4096×4096 decoded pixels, SHA-256 verification and content-addressed storage. Wire chunks are at most 32 KiB, paced and subject to a 64 MB per-direction connection budget. Only the selected background can be requested; arbitrary paths are never accepted. Existing back-image bounds remain in effect.

The host sequences shared cosmetic background edits only; this does not grant gameplay ownership. Clients retain sleeve-approval enforcement, authenticated recovery and existing match epochs. No deployment or distant public-relay acceptance is claimed.
