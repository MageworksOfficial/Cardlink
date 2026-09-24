# CardLink service hosting
The Python service handles room-code signaling and a separate bounded, schema-validated TCP/TLS relay. It is not a game rules authority. Current relay schemas include approved public actions and consent-controlled transfer paths; private hands/library order must not become unrestricted snapshots. Review service/relay_protocol.py and service tests before changes.

## Current public configuration
Service: https://35-208-120-243.sslip.io:8787
Relay host: 35-208-120-243.sslip.io, TCP/TLS port 8788.
These are public client endpoints, not administrator credentials. Never disable hostname/certificate verification.

## Ubuntu operator example
Install Python 3.11+; create a dedicated unprivileged cardlink user. Place reviewed service/cardlink_service.py and service/relay_protocol.py under /opt/cardlink. Run unit tests before deployment. Copy deployment/cardlink.service to the systemd unit directory, and adapt deployment/service.env.example to /etc/cardlink/service.env with your real hostname and certificate paths. Keep runtime environment files out of source control.

Provision a trusted certificate separately; give only the service account required read access. Open inbound TCP 8787 and 8788; restrict administrative access separately. The supplied systemd unit uses hardening and an isolated journal namespace. Review deployment/journald@cardlink.conf and renew-cardlink.sh before installing. Configure safe certificate renewal/reload; never publish a private key. Use systemctl daemon-reload and enable/start only after operator review. Verify HTTPS health, room creation/lookup, relay handshake, disconnect and expiry with separate test clients.

The example limits rooms to 32 and sets MemoryMax=384M with bounded traffic/queues. These are safeguards, not a measured capacity promise. Budget bandwidth for authorized Card Sync transfers, monitor memory/CPU/traffic, and load-test on staging before expanding. Certificate lifecycle, abuse handling and availability remain operator responsibilities.

## 7.7 update
SERVER_77_UPDATE.md describes the narrow relay-validator update; do not replace cardlink_service.py merely to apply that patch. Live installation is an operator task and has not been confirmed by this Beta preparation.

## Service longevity and future roadmap
The current online server is provided for testing and community use. Its uptime and long-term availability are not guaranteed. Multiple selectable community servers, volunteer relay operators, donated capacity and automatic fallback are future roadmap ideas, not current features.

A future server browser might show name, region, ping, players/rooms, capacity, relay load, version, official/community designation and status. Selection/fallback and approved volunteer relays are not implemented. This guide does not deploy or modify any live service.

## License
CardLink client/server source is licensed under the [GNU General Public License v3.0 (GPL-3.0)](LICENSE). Distributing modified versions must comply with GPL-3.0. Include the license and applicable notices with distributions. This does not relicense third-party game content or dependencies; see [THIRD_PARTY_NOTICE.md](THIRD_PARTY_NOTICE.md).
