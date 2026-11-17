# Interchange and integration plan

Status: planning only · 2026-11-16

## Principle

The local `.tex` or `.md` file and its project folder are the source of truth. Compile/render and edit work offline. Every conversion creates a separate copy, shows a result summary, and leaves the original untouched. A cloud account is required only when the user chooses a cloud action. Do not claim bidirectional sync until there is a reliable conflict and fidelity model.

The name “libretext” is interpreted here as **LibreTexts**, the education publishing platform. **LibreOffice Writer** is covered separately through ODT. Confirm the intended product before implementing a provider-specific connector.

## Priority and path

| Destination/source | First useful path | Later path, only if proven | Main risk |
| --- | --- | --- | --- |
| Microsoft Word | Import/export `.docx` as a copy via user-installed Pandoc | Better style mapping with a reference DOCX | Custom LaTeX macros, layout, citations, and comments may change |
| LibreOffice Writer | Import/export `.odt` as a copy via Pandoc | Open exported ODT in Writer for manual review | Same conversion losses; do not mistake Writer for LibreTexts |
| Google Docs | Export `.docx` or PDF, then let the user upload; import a Google Doc by first exporting it to `.docx` | Opt-in Google Drive sign-in and per-file transfer | Internet/OAuth, conversion loss, remote edits and conflicts |
| LibreTexts | Export reviewable HTML/EPUB or DOCX copy and hand off to its authoring flow | A supported authenticated publish flow after partner/API validation | Attribution, license, page structure, math, and images |
| Zotero | Read a `.bib` file exported by Zotero; offer citation-key completion | Optional local Zotero connector | Key stability and bibliography ownership |
| Git/Overleaf | Keep ordinary project files so Git works directly | No special connector needed initially | Merge conflicts are managed by Git/Overleaf, not the editor |

Pandoc documents LaTeX, DOCX, ODT, HTML and EPUB readers/writers; its handling of LaTeX macros and DOCX styles is format-dependent. Treat it as a conversion engine, not a lossless document model. [Pandoc manual](https://pandoc.org/MANUAL.html). LibreOffice documents DOCX and ODT filters if a user prefers its command-line conversion, but there is no reason to require LibreOffice for the first connector. [LibreOffice conversion filters](https://help.libreoffice.org/latest/en-US/text/shared/guide/convertfilters.html).

Word can accept some LaTeX syntax inside its equation editor, but this is not equivalent to opening an entire `.tex` project with packages, macros, bibliography and layout. [Microsoft's equation support](https://support.microsoft.com/en-gb/word/linear-format-equations-using-unicodemath-and-latex-in-word).

## Google Docs

**First version:** no account integration. The user exports DOCX or PDF, reviews it, and uploads it manually. For import, they export a Google Doc as DOCX and import that copy. Google Drive officially supports export of Docs to DOCX, ODT, PDF, HTML and other formats; its upload API can convert DOCX, ODT, HTML, RTF, text and Markdown to Google Docs. It does not list native LaTeX as an import format. [Drive export formats](https://developers.google.com/workspace/drive/api/guides/ref-export-formats), [Drive upload and conversion](https://developers.google.com/workspace/drive/api/guides/manage-uploads).

**Optional account connector:** use desktop OAuth and the narrow `drive.file` scope for user-selected files. Upload an exported copy as a *new* Google Doc. Download a selected Doc as DOCX for import into a *new* local workspace. Store OAuth tokens in macOS Keychain, make sign-out and token deletion available, and never upload during ordinary Build. Google describes `drive.file` as per-file access and notes verification requirements for broader scopes. [Drive scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth), [installed-app OAuth](https://developers.google.com/identity/protocols/oauth2/native-app).

Do not update an existing Google Doc by file conversion in an early release: Google states that media conversion during an update replaces the document's full contents. Remote edits and comments need an explicit conflict strategy before that is safe. [Drive upload and conversion](https://developers.google.com/workspace/drive/api/guides/manage-uploads).

## LibreTexts

LibreTexts' own construction guide says its team selects an integration path based on whether the source is PDF, Word, Google Docs or LaTeX; authors can also edit page HTML in the platform. Its publishing workflow includes accessibility, attribution and license review. That supports a **reviewed handoff**, not a promise of one-click publishing. [Contribution guidance](https://socialsci.libretexts.org/Bookshelves/Open_Education/LibreTexts_Construction_Guide_3e/13%3A_Contributing_Harvesting_and_Curating_Content/13.04%3A_Contributing_Existing_Content_%28FAQ%29), [publishing guide](https://socialsci.libretexts.org/Bookshelves/Open_Education/LibreTexts_Construction_Guide_3e/07%3A_Introduction_to_Publishing/7.01%3A_Publishing_Your_LibreTexts_Book_or_Project).

The LibreTexts project repository documents import services for EPUB, Common Cartridge, PDF and PreTeXt, with elevated endpoints and permissions. It does not establish a public, stable desktop publishing API for arbitrary users. A direct publish connector needs confirmation from LibreTexts maintainers, supported authentication, licensing, content hierarchy, image upload and equation fidelity before any UI promise. [LibreTexts API repository](https://github.com/LibreTexts/Libretext/blob/master/API/README.md).

For reusing LibreTexts content in a local project, require the user to select content with a compatible license and preserve attribution. Start with download/open of a book's offered export rather than scraping pages. LibreTexts documents book export through its download/compilation flow. [LibreTexts download guide](https://chem.libretexts.org/Courses/Remixer_University/Construction_Guide_for_LibreTexts_2e/09%3A_Advanced_Editing/9.06%3A_Compiling_Batching_and_the_Download_Center).

## Conversion contract

1. User chooses **Import a copy** or **Export a copy** from File. Show source and destination paths.
2. Verify the converter is installed. If absent, explain how to install it; editing and PDF export keep working.
3. Run conversion into a temporary location. Never overwrite the source or a previous export silently.
4. Show a summary: files created, images found/missing, equations, citations, unrecognized/raw LaTeX, conversion warnings. If a reliable count is unavailable, state that manual review is required rather than inventing one.
5. Let the user inspect the generated document and choose the final destination. Keep the conversion log with that session.

The first fidelity corpus should include an article, a multi-file thesis, a math-heavy paper, a citation-heavy paper, and a LibreTexts-like chapter with images and alt text. Review headings, equations, tables, figures, references, footnotes, links, styles and accessibility in the target app. Acceptance means no silent data loss and clear limitations; byte-for-byte round trips are not a realistic requirement for different document models.

## Deferred integrations

- Zotero's supported BibTeX export provides a simple starting point for citations. A live account or local API connector is optional after file-based completion works. [Zotero export guide](https://www.zotero.org/support/kb/exporting), [Zotero API formats](https://www.zotero.org/support/dev/web_api/v3/basics).
- Overleaf can work with Git repositories through its Git integration, which is a premium feature for its cloud product. NativeLatex only needs to preserve ordinary files and play well with Git; do not imply free or automatic Overleaf sync. [Overleaf Git integration](https://docs.overleaf.com/integrations-and-add-ons/git-integration-and-github-synchronization/git-integration/advanced-git-operations).
