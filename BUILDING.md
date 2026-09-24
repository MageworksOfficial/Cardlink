# Building CardLink 7.8.1 Beta
Use Godot **4.7.2 stable** and matching export templates. Import project.godot in the editor, allow resource import, then run the application_shell startup scene. Python **3.11+** standard library runs the service and its tests.

## Structure
scripts/ contains models/UI/integrations/networking/tests; scenes/ and ui/ contain Godot scenes; assets/ contains source visuals; config/network.cfg is shipped configuration; service/ contains the Python service/validator; deployment/ contains operator templates. Do not rearrange resource paths casually.

## Export
Use Project → Export → MILESTONE for Windows x86_64; choose a new output directory, keep EXE/PCK together. Use macOS preset for Universal arm64/x86_64, bundle identifier com.vexmageworks.cardlink, ad-hoc signing. ETC2/ASTC project import support is enabled. Notarization/Apple paid signing are not configured. Native Mac testing is required before a public Mac release.

Both presets include config/network.cfg. Their exclusion list protects legacy card images/reference-only artwork; do not remove it when exporting. Existing local builds are not automatically safe public releases. Include CREDITS.md and THIRD_PARTY_NOTICE.md with release packages.

## Tests
Run `python -B -m unittest discover -s service -p "test*.py"`.
Run Godot tests with `godot --headless --path . --script res://scripts/tests/milestone_78_test.gd -- <absolute-isolated-output-directory>` and the relevant earlier suites. The Beta presentation test is `beta_prep_test.gd`. Graphical and two-client tests need their documented harness/environment. Avoid live service tests in CI. CI currently runs server and repository-safety checks; full Godot CI is deferred pending a reliable engine/template setup.

## User data and versions
Godot user:// resolves to the OS-specific application data directory (normally Godot/app_userdata/Cardlink). It contains personal cards, decks, preferences, caches and saves; never commit it. Use isolated test directories.

scripts/frontend/app_info.gd defines current version 7.8.1, channel Beta and empty PROJECT_URL. Set the real project URL only after publication is approved. Network compatibility 7.7/protocol 1 is intentionally separate. Update generated public version headings when changing the central version.

## Configuration
Production config uses the public HTTPS service and verified TLS relay. For development, use a separate local copy/config pointing to loopback HTTP and the development service; insecure transport is limited to loopback. Preserve production values in the release build. No certificate bypass is supported. See SERVER_HOSTING.md. Never commit server keys, credentials, live environment files or session tokens.

## License
CardLink client/server source is licensed under the [GNU General Public License v3.0 (GPL-3.0)](LICENSE). Distributing modified versions must comply with GPL-3.0. Include the license and applicable notices with distributions. This does not relicense third-party game content or dependencies; see [THIRD_PARTY_NOTICE.md](THIRD_PARTY_NOTICE.md).
