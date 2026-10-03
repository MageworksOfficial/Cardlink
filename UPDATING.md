# Updating CardLink

CardLink's **Update Service**, future **Server Directory**, and **Gameplay Server** are separate concerns. A selected gameplay relay, region, room host or future community server cannot select the update source. GitHub Releases hosts packages and release notes; it is not the manifest service.

## Current client configuration

`config/update.cfg` contains one `updates.update_service_url`:

`https://35-208-120-243.sslip.io:8787/v1/update`

It is independent of `config/network.cfg` (`service_url`, `relay_host`, `relay_port`). `CARDLINK_UPDATE_SERVICE_URL` is an optional operator override; ordinary relay selection does not change it. Both Windows and Mac export presets include update.cfg. `github_repository` restricts release and package links to `MageworksOfficial/Cardlink`.

The client compares `AppInfo.UPDATE_VERSION` (`0.8.5.1`) with source-milestone versions such as `0.8.6`, numerically, supporting three or four components. Do not substitute the legacy bundle/technical identifier `7.8.1` for this version stream. Wire compatibility remains 7.7/protocol 1.

## Check and download flow

- One quiet asynchronous check starts with the title screen. HTTP timeout is 8 seconds; maximum response is 64 KiB. HTTPS hostname and certificate verification remain enabled; redirects are refused.
- Click the bottom-right version/status area, or Settings → Check for Updates. Text/icons distinguish Checking, Up to Date, Update Available, Update Required and Update Status Unavailable. Available/Required gently pulse over 3.2 seconds; Reduce Motion uses a static highlight.
- Online entry rechecks stale metadata. Consecutive failed checks are coalesced for 30 seconds to avoid repeated waits during one entry flow; manual Check Again can retry immediately. No periodic network polling occurs.
- A valid minimum-online policy can retire this client from new online entry. The dialog explains the restriction; Offline remains available. Existing matches are not forcibly disconnected. Host/Join and the playtest-to-online shortcut also consult the updater.
- Update Now opens a validated platform package URL at GitHub in the browser. Download and install manually. This milestone does not replace running executables, install packages or automatically verify downloaded bytes. Expected size and SHA-256 come from the manifest (checksum in the button tooltip); verify the downloaded archive against that checksum before replacing a build. Keep your local collection/saves and older build.
- Release Notes/View Releases opens the configured GitHub project. If no package for the platform is announced, Update Now is disabled with an explanation.

## Cache and failure policy

`user://updates/manifest.json` stores the endpoint, check time and last validated public metadata. Writes use existing atomic storage. Cache files larger than 64 KiB, malformed schemas, mismatched endpoint or unreasonable future times are ignored. Arbitrary fields and the unused optional directory location are not retained.

A successful check is fresh for four hours. On a failed check, a recent valid cache can show cached status, including a recent required-update policy. Stale required policy is refreshed before entry; if refresh fails, show unavailable and allow entry rather than retiring the client indefinitely. This is a client availability policy, not a substitute for gameplay protocol checks. Gameplay connection can still fail for its own independent reasons.

No account, deck, card identity, library order, match state or player nickname is transmitted by the updater. It sends only an ordinary unauthenticated GET. Cached latest-version text can appear in an unavailable dialog as the last-known value; it is not treated as fresh policy.

## Manifest contract

Required fields: `latest_version`, `minimum_online_version`, `update_level` (`optional`, `recommended`, `required`), `release_url`, and an `assets` object. Platform keys currently used are `windows-x86_64`, `macos-universal`, `linux-x86_64`. Each announced asset requires a GitHub `url`, 64-hex `sha256`, and integer byte `size` (1–10 GiB). Package and release URLs must be under the configured GitHub repository's releases paths. Minimum cannot exceed latest. The minimum controls online retirement; update_level labels the announcement.

An optional HTTPS `server_directory_url` is accepted but ignored by the client. `directory.server_directory_url` in update.cfg reserves a future independent config field. There is no server discovery, ping, listing, capacity service or community relay browser in this milestone.

## Prepared manifest and release gate

`service/update_manifest.json` announces the current local source milestone 0.8.5.1, with minimum 0.0.0 (no retirement policy imposed) and no assets. The user-supplied release page remains the historical `v7.8.1_beta` page. GitHub inspection found a 7.8.1 Windows ZIP and tutorial PDF, not a V0.8.5.1 package or Mac package. That older ZIP is deliberately **not** advertised as this update.

Before publishing an upgrade announcement, export/test the matching version, publish its genuine GitHub release and platform ZIPs, then replace release_url and populate assets with their actual URLs, byte sizes and SHA-256. Do not invent hashes or label old binaries as a newer source milestone. Policy changes to minimum-online version are explicit operator decisions. No GitHub upload or client export occurred here.

## Hosting and migration

See SERVER_HOSTING.md and SERVER_V0851_UPDATE.md. The metadata validator/cache is a standalone module with no room/relay imports. The temporary GET route shares the existing host/HTTPS listener, but is not derived from gameplay configuration or room state. A whole-machine or shared-process failure can still affect both services during this temporary co-hosting arrangement.

For future separation, serve the same validated JSON from a dedicated HTTPS/static front end under an operator-owned stable hostname. Backends can then move behind that hostname without changing any gameplay relay. The current sslip.io hostname encodes its IP; it cannot be repointed like a DNS name you own. Moving to a new hostname requires a client config update (or operator override), and keeping the old endpoint available through the transition. No real future domain is invented here.

## Current live limitation

The September 28, 2026 HTTPS check of the planned endpoint failed with `CERTIFICATE_VERIFY_FAILED: certificate has expired`. No TLS bypass was used, and whether the route is already deployed could not be established through that failed connection. Server changes are prepared only. Repair the live certificate and deploy/verify separately before expecting successful production checks.


### V0.8.5.1 release preparation

The client and local server validator accept the explicit `-beta` suffix on three/four-part numeric versions. Stable sorts after beta at the same numeric version; other suffixes remain rejected. Installed update version is `0.8.5.1-beta`. See CARDLINK_V0851_FRIDAY_RELEASE_PREP.md for clean exports and real hash/size metadata. Pending manifests with missing public URLs deliberately fail validation; synthetic local fixtures must never be deployed. The older prepared server ZIP predates this suffix adjustment. No live manifest/minimum or retirement policy changed.
