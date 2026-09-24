# Contributing
Public contribution links will be added after the repository is created. Until then, keep proposals local. Read FEEDBACK.md, SECURITY.md and CODE_OF_CONDUCT.md.

Use Godot 4.7.2 stable and matching export templates. Prefer typed GDScript, small modular components and narrowly scoped changes. Keep tabletop state separate from transport and UI. Favor generic manual tools over one game's rules.

For a change, explain the problem and resulting behavior, run relevant tests under scripts/tests with isolated output directories, and run Python service tests for networking/schema changes. Include Windows results and Mac results where relevant; explicitly identify tests you could not run. Preserve old saves where practical, app/wire version separation, TLS verification, consent and hidden-state boundaries. Never send private snapshots merely to simplify synchronization.

Do not contribute leaked credentials, copyrighted card-image collections, publisher logos without permission, scraped commercial site archives or personal user data. Use generated generic test graphics. No live production deployment in pull requests. By contributing code or content that you have the right to contribute, you agree that those contributions may be distributed as part of CardLink under the GNU General Public License v3.0 (GPL-3.0). See [LICENSE](LICENSE). Do not submit third-party assets without appropriate rights; CardLink’s license does not override their original licensing.
