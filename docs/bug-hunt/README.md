# Bug hunt (in progress)

Six read-only hunters, started 2026-10-30, each from a different angle than the [code audit](../audit/README.md) (they skip anything the audit already found). Each writes its own report here; when all six are done, this page gets a triaged list of what to fix.

| # | Angle | Report | Status |
|---|---|---|---|
| 1 | Regressions in the last day's commits | [01-regressions.md](01-regressions.md) | In progress |
| 2 | The new Windows native code (tray, quit, taskbar, single copy, keep-awake) | [02-windows-native.md](02-windows-native.md) | In progress |
| 3 | Real server flows against the throwaway test server (plus new integration tests) | [03-server-flows.md](03-server-flows.md) | In progress |
| 4 | Saved data: preferences, migrations, accounts, backup and restore | [04-persisted-data.md](04-persisted-data.md) | In progress |
| 5 | Error paths and races (slow or failing server, fast clicks) | [05-error-paths.md](05-error-paths.md) | In progress |
| 6 | The web version | [06-web.md](06-web.md) | In progress |
