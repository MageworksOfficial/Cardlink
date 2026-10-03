# Custom table relay update — prepared locally, not deployed

This optional extension accepts validated custom table layouts, referenced board-image chunks, pile counts, draw requests and public placement messages. It does not send entire private pile orders or hand lists. Individual intentional draws use the existing acknowledged private transfer transaction.

Required server files, kept together in the existing service directory:

- `service/relay_protocol.py` — updated dispatcher, retains existing protocol checks.
- `service/table_protocol.py` — new strict custom-table envelope and data validator.

`service/cardlink_service.py` remains unchanged. Do not substitute older relay validators or upload only the dispatcher without its new dependency. Existing single/multi-face validators remain required in the server directory.

Optional verification files: `service/test_table_protocol.py`, with the existing `test_service.py` and `test_faces.py`. Run `python3 -m unittest test_service test_faces test_table_protocol` from that directory before restarting. The local run passed 27 tests.

Operator checklist for a later authorized deployment:

1. Back up the existing relay validator and record the running service configuration.
2. Review and upload the two required files into the existing service directory; preserve permissions, TLS certificate paths and service configuration.
3. Run the tests with existing dependencies, then restart the existing CardLink systemd unit using its actual configured name.
4. Verify normal room/relay connections, then test custom table structure, board transfer and a shared draw with two updated clients. Confirm unrequested private hand/pile identities stay hidden.
5. If validation fails, restore the backed-up validator and restart the same unit.

No server access, restart, TLS change or live test was performed by this source milestone. Protocol 1 / compatibility 7.7 remain unchanged; custom tables require matching updated clients, while Standard retains its prior path. No NAT, matchmaking or automatic rules were added.
