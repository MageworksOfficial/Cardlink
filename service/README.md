# CardLink room service and relay
See [Server hosting](../SERVER_HOSTING.md) for current deployment/configuration and privacy guidance. The earlier handshake-only prototype description is superseded: the current validated relay supports approved public actions and controlled Card Sync traffic.

Python 3.11+ standard library only. Local development: `python -B service/cardlink_service.py` (loopback defaults). Tests: `python -B -m unittest discover -s service -p "test*.py"`. Use a separate development client configuration, not the production export.

Review relay_protocol.py for bounded schemas and privacy rejection. Do not add private hand identities or ordered libraries to unrestricted messages. No live deployment occurs automatically.

CardLink service source uses [GNU GPL-3.0](../LICENSE). Third-party material retains its original rights and licensing.
