# V0.8.5.1 Update Service deployment checklist — PREPARED ONLY

Planned manifest URL: https://35-208-120-243.sslip.io:8787/v1/update

No live file, certificate, service or GitHub release was changed. The HTTPS verification attempt failed because the live certificate was reported expired. Keep certificate verification enabled.

## What changed

`cardlink_service.py` gains one narrowly routed **GET /v1/update** handler. It delegates to new `update_manifest.py`, which has no room/relay imports and serves only validated operator-owned JSON. Existing POST room routes and relay logic are unchanged. Manifest JSON is reread at most every 10 seconds on demand and cached in memory. A missing/invalid manifest returns only `update_status_unavailable`; rooms remain usable. Existing connection/rate bounds still cover the shared listener.

This changes cardlink_service.py for the new HTTP endpoint, unlike the earlier validator-only 7.7 update. `relay_protocol.py`, `battle_protocol.py`, `table_protocol.py`, and `appearance_protocol.py` are included as current dependencies, unchanged by this milestone. Do not accidentally replace these dependencies with historical older copies. The package does not imply that the earlier appearance update has already been deployed.

## Upload and verify (operator steps, not executed)

1. Back up the current Python files and service configuration on the Linux server. Preserve TLS keys/certificates and the current unit/environment file; they are not in this package.
2. Repair/verify the trusted TLS certificate for the hostname using your existing certificate procedure. Inspect the active certificate first. Do not bypass hostname or chain verification.
3. Extract this update package into a staging directory. Verify SHA256SUMS. Review the diff of cardlink_service.py against the deployed service.
4. Required new endpoint files: `cardlink_service.py`, `update_manifest.py`, `update_manifest.json`. Keep the supplied current relay/battle/table/appearance dependencies beside them if upgrading from an older deployment. Optional tests: the six `test_*.py` files supplied. Do not upload client code or user collections.
5. Run `python3 -B -m unittest test_service test_faces test_table_protocol test_battle test_appearance test_updates` from the staging directory. The local reference result is 54 passing tests. The metadata HTTP tests use only loopback, not the live service.
6. Review the manifest before activating it. It is a **source milestone preview with no download assets**. It must not advertise the old 7.8.1 archive as V0.8.5.1. Publish matching packages separately, then populate their real URLs/size/SHA-256 and correct release page. Current minimum is 0.0.0; no forced retirement is introduced by the shipped JSON.
7. Install reviewed files in the existing application directory. By default, update_manifest.json lives beside update_manifest.py. Optionally use `CARDLINK_UPDATE_MANIFEST=/absolute/operator/path/manifest.json` (or `--update-manifest`) to locate policy separately. The file is public metadata, not a secret store.
8. Restart the existing CardLink systemd unit only after review. Unit/ports/certificate paths need not change for this temporary co-hosted route. Verify `curl --fail https://35-208-120-243.sslip.io:8787/v1/update` with normal TLS, then existing POST /v1/health, room flow and relay probe.
9. Launch an updated client. Check status, manual retry, offline availability and update-service failure independently of gameplay. There is no auto-install step.
10. Rollback: restore the backed-up complete Python set/config and restart that service. Older gameplay service may not serve GET /v1/update; the new client safely shows unavailable and retains local play.

## Separation and future hosting

Update Service = version policy/metadata. Server Directory = future listings. Gameplay Server = rooms/traffic. Client update.cfg is independent of network.cfg, even while both services temporarily share the same address. Future community relay selection cannot override updates.

To host metadata independently, reuse `update_manifest.validate` with the same bounded schema and serve its JSON through a separate HTTPS/static front end. It requires no Rooms instance, relay sockets, database or account system. Move behind a stable hostname you control; preserve the old configured URL during rollout. Current sslip.io naming is tied to the public IP, so a new hostname needs a client config migration. Optional manifest server_directory_url remains unused. No directory implementation is supplied.

## Download flow

The update HTTP route never streams installers. GitHub hosts released packages and notes. The client restricts URLs to the configured repository, uses normal HTTPS for metadata, and displays validated expected file metadata. Update Now opens a browser; download/install and checksum verification remain manual in this milestone.
