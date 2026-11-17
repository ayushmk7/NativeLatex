# NativeLatexIntegrations

Local import/export for LibreWeave (macOS 14+). Every conversion writes a **new copy**; sources are never modified and existing copies are never overwritten (`name 2.docx`).

| API | Engine | Notes |
| --- | --- | --- |
| `LocalConverter().convert(_:to:in:)` | Pandoc: tex/md/html ↔ docx/odt/tex/md/html; LibreOffice: docx ↔ odt, docx/odt → pdf | Args passed as arrays, no shell; temp work dir; images extracted to `<name>_media/` with relative links; `reviewNotes` flags known losses |
| `GoogleDocsIntegration(enabled:transport:)` | `GoogleDriveTransport` protocol | No live transport ships: status is `.disabled` or `.liveNotConfigured`. Tests use a fake |
| `LibreTextsClient().importPage(_:as:into:)` | Public Deki API, no key | Import only; refuses pages without a reusable `license:` tag; adds attribution |

Test (real Pandoc/LibreOffice; skipped if absent):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
NATIVELATEX_LIVE_NETWORK=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter testLivePublicPage
```

Fixtures come from `docs/research/conversion-fixtures` (shared with the [conversion test](../../docs/research/conversion-test-2026-11-17.md)).
