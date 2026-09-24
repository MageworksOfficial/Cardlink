# CardLink 7.7 relay validation update

The public relay checks message schemas. Its current validator rejects multi-face definitions and face indices, which closes the connection during Card Sync. Both 7.7 clients and this small relay validator update are required for multi-face internet play.

This update replaces only relay_protocol.py. It accepts an optional bounded face list in asset descriptors and an optional 0–15 face index in public card records/patches. It still rejects filesystem paths, arbitrary fields and private snapshots. Existing single-face schemas remain accepted. No service ports, TLS settings, certificates, account data, room routing or server architecture change.

Use the existing server access method. Unzip CardLink-7.7-Relay-Update.zip into a temporary folder on the Linux host. The supplied deployment uses /opt/cardlink/relay_protocol.py; confirm with `systemctl cat cardlink` if your installation differs.

From the unpacked folder:

```sh
python3 -B -m unittest test_faces -v
sudo cp -a /opt/cardlink/relay_protocol.py /opt/cardlink/relay_protocol.py.pre-7.7
sudo install -o root -g root -m 0644 relay_protocol.py /opt/cardlink/relay_protocol.py
sudo systemctl restart cardlink
sudo systemctl is-active cardlink
curl --fail https://35-208-120-243.sslip.io:8787/v1/health -H 'Content-Type: application/json' -d '{}'
```

Restarting disconnects active sessions; do this between games. No certificate renewal is needed for this schema update. Keep TLS verification enabled. Do not replace cardlink_service.py or the environment configuration.

To roll back this validator only:

```sh
sudo cp -a /opt/cardlink/relay_protocol.py.pre-7.7 /opt/cardlink/relay_protocol.py
sudo systemctl restart cardlink
```

After installation, test two 7.7 clients: Host/Join by room code, Card Sync a deck with two faces, play it, change its face from each client, and reconnect while the alternate face is public. Earlier client versions can still play with matching earlier versions; the 7.7 client compatibility check prevents mixed-version sessions.
