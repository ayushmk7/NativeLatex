# AWS hosting and cost plan

Status: planning only · 2026-11-16. No AWS resources are provisioned.

## Boundary

NativeLatex runs on each Mac, iPad, or iPhone. Editing, local preview, TeX compilation, and user-chosen file storage stay on the device or in its Files provider. AWS hosts only things that need a public endpoint. This lets the app work offline and avoids a per-build server bill.

| Need | First path | Cost boundary |
| --- | --- | --- |
| Project website, documentation, Mac download | Static files in a private S3 bucket behind CloudFront | Evaluate CloudFront's $0/month flat-rate Free plan; it includes 1 million requests, 100 GB transfer, and 5 GB S3 Standard storage credits per month. S3 usage beyond credits and unrelated AWS services can still cost money. |
| Mac app distribution | Signed and notarized download from the website | Apple Developer Program membership is needed for Developer ID distribution. |
| iPhone/iPad distribution | App Store and TestFlight | Apple distributes these apps; AWS does not replace App Store distribution or its developer membership. |
| Google Docs, OneDrive, Crossref | User-authorized client calls from the native app | No AWS API server for ordinary file transfer or DOI lookup; provider quotas and user subscriptions still apply. |
| Sync, accounts, collaboration | Design and price only when explicitly chosen | S3, auth, database, traffic, and operations would create an ongoing service and cost obligation. |

CloudFront's flat-rate Free plan has published allowances, no overage charges for covered delivery, and possible delivery adjustments after sustained high usage. Its 5 GB S3 credit offsets S3 Standard storage costs; it is not a blanket free AWS account. Use a private bucket with Origin Access Control and measure any service outside the plan before launch. [CloudFront plan details](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/flat-rate-pricing-plan.html), [CloudFront pricing](https://aws.amazon.com/cloudfront/pricing/).

AWS's separate new-account Free plan lasts at most six months or until credits run out. It is useful for evaluation, not a long-term hosting budget. [AWS Free Tier FAQ](https://aws.amazon.com/free/free-tier-faqs/). Apple lists the Developer Program at US $99 per membership year (local price may vary). [Apple enrollment](https://developer.apple.com/help/account/membership/program-enrollment/).

## Release decision

Start with the native app and static distribution. Add an AWS runtime only after a feature needs shared state; then prepare a monthly estimate, usage alarms, retention policy, and an exit path for user documents before implementation. Keep the product usable if that runtime is unavailable.
