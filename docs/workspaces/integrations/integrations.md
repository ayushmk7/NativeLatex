# Interchange and integration plan

Status: plan, with a local package implemented · revised 2026-11-17 · Mac only

## Implemented in `NativeLatex/Integrations` and linked into the app

The Swift package (macOS 14+) is described in its [README](../../../NativeLatex/Integrations/README.md). `swift test` on merged main: 17 tests pass and 1 live LibreTexts network test is skipped by default (opt in with `NATIVELATEX_LIVE_NETWORK=1`). Conversion tests use the real Pandoc and LibreOffice on this Mac and skip when a tool is absent.

| Piece | Implemented behavior | Not done |
| --- | --- | --- |
| Local conversion | Pandoc: tex/md/html ↔ docx/odt/tex/md/html. LibreOffice: docx ↔ odt, docx/odt → pdf. Argument arrays, no shell, temp work dir, timeout. Always writes a new copy (`name 2.docx`), never touches the source or an existing copy. Images extracted to `<name>_media/` with relative links. App: File ▸ Export Copy / Import Copy shows the review notes and offers Open Copy or Show in Finder. | Word itself never tested |
| Google Docs | `GoogleDocsIntegration` behind a `GoogleDriveTransport` protocol. **No live transport ships**: status is `.disabled` or `.liveNotConfigured`, and the app's **Google Docs: Not Connected…** item only explains that. Only a fake transport is exercised in tests. No OAuth client, token, or Google API call exists. | Live sign-in, Drive upload/download |
| LibreTexts | **Import only** (File ▸ Import LibreTexts Page), from the public Deki API without a key. Refuses pages without a reusable `license:` tag and adds attribution. | Publishing or export handoff to LibreTexts |
| OneDrive | Nothing implemented. | Everything |

### Fidelity notes the converter reports

`LocalConverter` returns `reviewNotes` based on the source and target, because Pandoc exits successfully while losing content (see the [conversion test](../../research/conversion-test-2026-11-17.md)):

- Cross-references (`\ref`, `\eqref`) become literal text or lose their targets.
- Equation numbers are dropped.
- Citations use Pandoc's default author-date style, not the document's bibliography style.
- Custom macros and environments are expanded or flattened; their definitions are not kept.
- Figure/table numbering and placement change; captions may become ordinary text.
- Code block language tags are not kept in office formats.
- Imported LaTeX does not reconstruct original macros, labels, equation numbering, or bibliography files.
- Remote images are linked, not downloaded, and need network access to display.

The sections below remain the plan.

## Principle

The local `.tex` or `.md` file and its project folder are the source of truth. Compile/render and edit work offline. Every conversion creates a separate copy, shows a result summary, and leaves the original untouched. A cloud account is required only when the user chooses a cloud action. Do not claim bidirectional sync until there is a reliable conflict and fidelity model.

Only the owner's provider accounts are in scope. Use direct, opt-in user sign-in; there is no shared account database, tenant administration, or AWS proxy. Provider request limits still exist, so a rejected transfer must leave the local source intact and offer a retry. They do not justify a quota dashboard for one person.

The name “libretext” is interpreted here as **LibreTexts**, the education publishing platform. **LibreOffice Writer** is covered separately through ODT. Confirm the intended product before implementing a provider-specific connector.

## Free integration choices

“Free” below means no separate fee for the integration itself at the stated usage level. A user may still pay for a provider account, storage, or Apple app distribution; hosting has its own limits. The [deployment plan](../../deployment-plan.md) keeps these costs separate.

| Choice | Useful app action | Cost and access boundary | Plan |
| --- | --- | --- | --- |
| Finder / Files providers | Open and save ordinary project folders, including a user-chosen iCloud Drive or other Files location | No app backend or provider API charge; the user's storage plan may have limits | Core |
| Pandoc and LibreOffice formats | Import/export DOCX, ODT, HTML, EPUB and Markdown copies | Local tools and formats; no service fee. Conversion fidelity needs review | File interchange |
| Git and Zotero BibTeX/BibLaTeX | Keep projects Git-friendly; read a bibliography exported by Zotero | Local files; no service fee or sign-in | Core and power workflow |
| Crossref REST API | Look up a DOI and propose a citation entry, with user review before writing `.bib` | Public API needs no sign-up; use its polite pool and respect rate limits. Metadata can be incomplete | Optional citation helper |
| Google Docs via Drive API | Explicitly import/export a selected document as a new copy | Standard Drive API use has no additional cost within quota; requires Google sign-in, OAuth setup and internet. Google plans charges for requests beyond quota later in 2026 | Optional connected exchange |
| Word / OneDrive via Microsoft Graph | Explicitly transfer DOCX copies from a user's OneDrive | Standard Graph operations have no additional API charge within limits and a qualifying user license; requires Microsoft sign-in and internet | Optional connected exchange |
| LibreTexts | Export a reviewable file for an authorized author to submit | File handoff can be free; direct publishing needs platform permission and a supported API | Handoff first |

Crossref documents public, no-sign-up access and recommends identification for its polite pool. [Crossref REST API](https://www.crossref.org/documentation/retrieve-metadata/rest-api/), [access options](https://www.crossref.org/documentation/retrieve-metadata/rest-api/access-and-authentication/). Zotero supports library or collection export and BibLaTeX quick copy. [Zotero export](https://www.zotero.org/support/kb/exporting), [BibLaTeX format](https://www.zotero.org/support/preferences/export).

Google says standard Drive API use has no additional charge but plans charges above request quotas later in 2026. Use the narrow `drive.file` scope, and check the published pricing before shipping the connector. [Drive API limits and pricing](https://developers.google.com/workspace/drive/api/guides/limits), [Drive scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth). Microsoft says standard Graph APIs are included within usage thresholds under user licenses; its OneDrive file endpoint supports delegated personal accounts. [Graph metering](https://learn.microsoft.com/en-us/graph/metered-api-overview), [OneDrive upload](https://learn.microsoft.com/en-us/graph/api/driveitem-put-content?view=graph-rest-1.0).

For native sign-in, request user consent in the app and keep tokens in the device Keychain. File conversion and direct provider APIs do not require an AWS proxy. Never place a provider client secret in the app. A server is justified only by a feature that actually needs server-owned credentials or shared state.

## Priority and path

| Destination/source | First useful path | Later path, only if proven | Main risk |
| --- | --- | --- | --- |
| Microsoft Word | Export `.docx` as a reviewable copy via user-installed Pandoc; import a separate copy only after fidelity checks | Better style mapping with a reference DOCX | Custom LaTeX macros, references, citations, layout, and comments may change |
| LibreOffice Writer | Export `.odt` as a reviewable copy via Pandoc; import a separate copy only after fidelity checks | Open exported ODT in Writer for manual review | Same conversion losses; do not mistake Writer for LibreTexts |
| Google Docs | Export `.docx` or PDF, then let the user upload; import a Google Doc by first exporting it to `.docx` | Opt-in Google Drive sign-in and per-file transfer | Internet/OAuth, conversion loss, remote edits and conflicts |
| LibreTexts | Export reviewable HTML/EPUB or DOCX copy and hand off to its authoring flow | A supported authenticated publish flow after partner/API validation | Attribution, license, page structure, math, and images |
| Zotero | Read a `.bib` file exported by Zotero; offer citation-key completion | Optional local Zotero connector | Key stability and bibliography ownership |
| Git/Overleaf | Keep ordinary project files so Git works directly | No special connector needed initially | Merge conflicts are managed by Git/Overleaf, not the editor |

Pandoc documents LaTeX, DOCX, ODT, HTML and EPUB readers/writers; its handling of LaTeX macros and DOCX styles is format-dependent. Treat it as a conversion engine, not a lossless document model. [Pandoc manual](https://pandoc.org/MANUAL.html). LibreOffice documents DOCX and ODT filters if a user prefers its command-line conversion, but there is no reason to require LibreOffice for the first connector. [LibreOffice conversion filters](https://help.libreoffice.org/latest/en-US/text/shared/guide/convertfilters.html).

The [local conversion test](../../research/conversion-test-2026-11-17.md) used Pandoc 3.13 and LibreOffice 26.8.3 on real DOCX/ODT outputs. Simple text, math, images, tables, and bibliography text rendered, but equation numbers and references broke, citation style changed, and imported LaTeX lost source semantics. Pandoc exited successfully without reporting those losses. Consequently, the first conversion UI must present DOCX/ODT as **reviewable copies** and flag risky structures; source PDF remains the faithful LaTeX export.

Word can accept some LaTeX syntax inside its equation editor, but this is not equivalent to opening an entire `.tex` project with packages, macros, bibliography and layout. [Microsoft's equation support](https://support.microsoft.com/en-gb/word/linear-format-equations-using-unicodemath-and-latex-in-word).

## Google Docs

**First version:** no account integration. The user exports DOCX or PDF, reviews it, and uploads it manually. For import, they export a Google Doc as DOCX and import that copy. Google Drive officially supports export of Docs to DOCX, ODT, PDF, HTML and other formats; its upload API can convert DOCX, ODT, HTML, RTF, text and Markdown to Google Docs. It does not list native LaTeX as an import format. [Drive export formats](https://developers.google.com/workspace/drive/api/guides/ref-export-formats), [Drive upload and conversion](https://developers.google.com/workspace/drive/api/guides/manage-uploads).

**Optional account connector:** use desktop OAuth and the narrow `drive.file` scope for user-selected files. Upload an exported copy as a *new* Google Doc. Download a selected Doc as DOCX for import into a *new* local workspace. Store OAuth tokens in macOS Keychain, make sign-out and token deletion available, and never upload during ordinary Build. Google describes `drive.file` as per-file access and notes verification requirements for broader scopes. [Drive scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth), [installed-app OAuth](https://developers.google.com/identity/protocols/oauth2/native-app).

For this owner's personal use, Google says verification is not mandatory below 100 users, though an unverified-app warning can appear. An external OAuth app left in **Testing** gets refresh tokens that expire after seven days; plan the owner's published-status setup and reauthentication flow before treating sign-in as persistent. This does not require an AWS auth service. [Google personal-use exception](https://support.google.com/cloud/answer/13464323?hl=en), [Google token expiration](https://developers.google.com/identity/protocols/oauth2).

Do not update an existing Google Doc by file conversion in an early release: Google states that media conversion during an update replaces the document's full contents. Remote edits and comments need an explicit conflict strategy before that is safe. [Drive upload and conversion](https://developers.google.com/workspace/drive/api/guides/manage-uploads).

## Microsoft OneDrive

For the owner's personal Microsoft account, use delegated Microsoft Graph file permission and explicit selection. Upload a newly converted DOCX copy to OneDrive or download a selected DOCX into a new local workspace. Do not overwrite a remote file or claim live Word synchronization. Microsoft documents personal-account support for file upload with delegated `Files.ReadWrite`; standard Graph operations have no additional API charge within the user's license limits. Keep tokens in Keychain and make disconnect available. [Graph file upload](https://learn.microsoft.com/en-us/graph/api/driveitem-put-content?view=graph-rest-1.0), [Graph metering](https://learn.microsoft.com/en-us/graph/metered-api-overview).

## LibreTexts

LibreTexts' own construction guide says its team selects an integration path based on whether the source is PDF, Word, Google Docs or LaTeX; authors can also edit page HTML in the platform. Its publishing workflow includes accessibility, attribution and license review. That supports a **reviewed handoff**, not a promise of one-click publishing. [Contribution guidance](https://socialsci.libretexts.org/Bookshelves/Open_Education/LibreTexts_Construction_Guide_3e/13%3A_Contributing_Harvesting_and_Curating_Content/13.04%3A_Contributing_Existing_Content_%28FAQ%29), [publishing guide](https://socialsci.libretexts.org/Bookshelves/Open_Education/LibreTexts_Construction_Guide_3e/07%3A_Introduction_to_Publishing/7.01%3A_Publishing_Your_LibreTexts_Book_or_Project).

The LibreTexts project repository documents import services for EPUB, Common Cartridge, PDF and PreTeXt, with elevated endpoints and permissions. It does not establish a public, stable desktop publishing API for arbitrary users. A direct publish connector needs confirmation from LibreTexts maintainers, supported authentication, licensing, content hierarchy, image upload and equation fidelity before any UI promise. [LibreTexts API repository](https://github.com/LibreTexts/Libretext/blob/master/API/README.md).

For reusing LibreTexts content in a local project, require the user to select content with a compatible license and preserve attribution. Start with download/open of a book's offered export rather than scraping pages. LibreTexts documents book export through its download/compilation flow. [LibreTexts download guide](https://chem.libretexts.org/Courses/Remixer_University/Construction_Guide_for_LibreTexts_2e/09%3A_Advanced_Editing/9.06%3A_Compiling_Batching_and_the_Download_Center).

## Conversion contract

1. User chooses **Import a copy** or **Export a copy** from File. Show source and destination paths.
2. Verify the converter is installed. If absent, explain how to install it; editing and PDF export keep working.
3. Run conversion into a temporary location. For imports, copy extracted media into the new workspace and rewrite references to relative paths. Never overwrite the source or a previous export silently.
4. Show a summary: files created, images found/missing, equations, citations, unrecognized/raw LaTeX, conversion warnings. If a reliable count is unavailable, state that manual review is required rather than inventing one.
5. Let the user inspect the generated document and choose the final destination. Keep the conversion log with that session.

The first fidelity corpus should include an article, a multi-file thesis, a math-heavy paper, a citation-heavy paper, and a LibreTexts-like chapter with images and alt text. Review headings, equations, tables, figures, references, footnotes, links, styles and accessibility in the target app. Acceptance means no silent data loss and clear limitations; byte-for-byte round trips are not a realistic requirement for different document models.

## Deferred integrations

- Zotero's supported BibTeX export provides a simple starting point for citations. A live account or local API connector is optional after file-based completion works. [Zotero export guide](https://www.zotero.org/support/kb/exporting), [Zotero API formats](https://www.zotero.org/support/dev/web_api/v3/basics).
- Overleaf can work with Git repositories through its Git integration, which is a premium feature for its cloud product. NativeLatex only needs to preserve ordinary files and play well with Git; do not imply free or automatic Overleaf sync. [Overleaf Git integration](https://docs.overleaf.com/integrations-and-add-ons/git-integration-and-github-synchronization/git-integration/advanced-git-operations).
