# LibreLeaf Mac release and deployment plan

Status: planning and readiness checks · 2026-11-17. A static landing page exists in `landing/`; no app, release artifact, AWS resource, or website has been deployed.

## What needs hosting

The native Mac app edits and builds locally. Its single owner can use Google Drive or OneDrive through optional, user-authorized client integrations. No account service, TeX server, database, or sync API is part of this release. A website is **optional**: it can explain the app and link to a download, but it does not run the app.

| Surface | Decision | Reason |
| --- | --- | --- |
| Mac app | Build locally in Xcode; distribute a signed, notarized ZIP | It launches the user's TeX tools and opens ordinary folders. |
| Download artifact | Private S3 origin behind CloudFront | Keeps the user's preferred AWS hosting for the released ZIP and checksum. |
| Landing page | Static `landing/` on GitHub Pages via `.github/workflows/pages.yml`, linking to the AWS artifact | No app runtime, login, or build step; the repository is public, so Pages needs no extra account. Vercel stays an alternative but its Hobby terms restrict commercial use. |
| Updates | Publish a new versioned ZIP and release notes manually | No updater service is needed for one owner. |

Vercel documents the [Hobby restriction](https://vercel.com/docs/plans/hobby). CloudFront's $0/month flat-rate Free plan currently includes a baseline of 1 million requests, 100 GB delivery, and 5 GB of S3 Standard storage credits per month; other AWS usage can still be charged. Serve a private S3 bucket through Origin Access Control and verify the actual billing configuration before publication. [CloudFront plan](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/flat-rate-pricing-plan.html). The separate AWS new-account Free plan expires after at most six months or when credits are exhausted. [AWS Free Tier FAQ](https://aws.amazon.com/free/free-tier-faqs/).

## Release sequence

1. **Local app gate:** create and run the Mac Xcode target on this machine; verify `.tex` and `.md` Open With, local TeX build, Markdown preview, two independent workspace windows, and both appearances. Test a Mac without TeX before calling the app distributable.
2. **Signing gate:** set the bundle identifier, version, minimum macOS, app icon, signing team, and Hardened Runtime. Obtain a valid Developer ID Application identity in the keychain. Archive Release and use Xcode Organizer's Developer ID/direct distribution workflow to notarize. This Developer ID release route requires signing and notarization under Apple's [notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution/). Apple lists its Developer Program at US $99/year, subject to local pricing. [Apple enrollment](https://developer.apple.com/help/account/membership/program-enrollment/).
3. **Artifact gate:** staple the notarization ticket to the app, package a versioned ZIP, and record SHA-256. Verify `codesign --verify --deep --strict`, `xcrun stapler validate`, and `spctl --assess --type execute` on the exported app. Download the ZIP to a clean Mac and repeat the launch/build/open checks. The [backend plan](workspaces/backend/architecture.md) has the exact Mac release path.
4. **AWS gate:** authenticate to the intended AWS account, choose the CloudFront plan, create the private S3 origin and distribution with Origin Access Control, upload only the verified ZIP/checksum, then download and hash the public artifact. Set a budget or usage alert for any paid resources. Publish no user project files.
5. **Landing gate:** `.github/workflows/pages.yml` uploads `landing/` as-is and deploys it with the official Pages actions on pushes to `main` that touch `landing/` (or by manual dispatch). It stays inert until the owner sets **Settings → Pages → Source** to **GitHub Actions**; the first run before that fails at deploy. The [static page](../landing/README.md) can then serve an honest in-development message and repository link at the `github.io` address; a custom domain is a separate decision. Add a version, download link, checksum, and Mac requirements only after the artifact gate passes.

## Current readiness on this Mac

| Check | Result |
| --- | --- |
| Xcode | 27.2 works with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; system `xcode-select` still points to Command Line Tools. |
| Local TeX and converter | `latexmk` and Pandoc are present; [DOCX/ODT conversion was tested](research/conversion-test-2026-11-17.md). |
| Apple signing | `notarytool` and `stapler` are available, but the current keychain reports **0 valid code-signing identities**. |
| AWS | CLI is installed, but the default profile did not have a valid `sts get-caller-identity` session during this check. |
| Landing hosting | Pages workflow is committed and passes `actionlint` 1.7.12, but Pages is not enabled and nothing has been pushed or deployed. Vercel CLI is not installed. |
| App artifact | No Xcode project or app executable exists yet, so signing, notarization, and public deployment cannot be run. |

The next executable milestone is a local Debug build, followed by the signing gate. Do not create a download URL for a nonexistent release.
