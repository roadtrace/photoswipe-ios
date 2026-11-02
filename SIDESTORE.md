# Build an IPA for SideStore

Requires an iPhone/iPad on iOS/iPadOS 17 or later and an already configured SideStore.
The IPA is deliberately unsigned: SideStore re-signs it with your Apple account.
No Apple credentials, certificates, provisioning profiles, or GitHub secrets are needed for this build.

## GitHub Actions from Windows

1. Open your fork's **Actions** tab and enable workflows if GitHub asks.
2. Select **Build SideStore IPA**, then **Run workflow**. Select `sidestore-build`
   while these build changes are on that branch. Pushing to that branch also starts a build.
3. After the run succeeds, download the **PhotoSwipe-SideStore** artifact from
   the run's summary. GitHub requires you to be signed in to download artifacts.
4. Extract the downloaded artifact ZIP. The installable file inside is
   `PhotoSwipe-unsigned.ipa`. Do not import the outer artifact ZIP into SideStore.
5. Transfer the IPA to Files on your iPhone. In SideStore's **My Apps**, use the
   add/import control to select it. Keep the local VPN required by your SideStore
   setup enabled during installation and refresh.
6. Launch PhotoSwipe and choose the photo-library access you want to grant.
   Start with a small set of expendable photos and test canceling a deletion first.

The artifact includes a SHA-256 checksum, build log, Xcode version, source commit,
and any uncommitted source changes. It is retained for 14 days. On Windows, compare
`Get-FileHash .\PhotoSwipe-unsigned.ipa -Algorithm SHA256` to the `.sha256` file.

With a free Apple account, normal SideStore limits apply: three active apps including
SideStore and a seven-day signing period that SideStore refreshes. See the
[SideStore FAQ](https://docs.sidestore.io/docs/faq).

## Build on a Mac

Select a full Xcode 16+ installation and run from the repository root:

```sh
bash scripts/build-ipa.sh
```

The script prints its unique `build/ipa.XXXXXX/artifacts` output directory.
It compiles Release for `generic/platform=iOS` with signing disabled, verifies
the device platform, arm64 executable, encryption flag and photo permission
descriptions, then packages `Payload/PhotoSwipe.app` using Apple's `ditto`.
No simulator app is packaged. Pipeline failures stop packaging.

## Safety review

Reviewed upstream revision: `d542440a6ecd1fbacce0ad335e84cac61fe1e2d1`.
Repository: https://github.com/noluyorAbi/photoswipe-ios
License: MIT, copyright 2026 Alperen Adatepe; preserved in LICENSE.
Latest upstream main commit: June 1, 2026 UTC (June 2 in Manila).
At review time there were three commits, no published releases, and three open PRs.
This is a small project with limited public maintenance history.

Static review found no app upload endpoints, analytics SDKs, third-party app
dependencies, bundled executables, custom Xcode shell phases, Git submodules,
or special app entitlements. Cloning and building the reviewed source appear
reasonable; this is not a guarantee of bug-free or malicious-behavior-free software.
The unrelated `promo` npm project is not installed or used by the IPA build.

Material limitations:

- PhotoKit can fetch iCloud-backed images (`isNetworkAccessAllowed = true`), so
  the upstream claim that it is entirely offline is too broad. No custom upload
  code was found.
- Photo deletion uses PhotoKit and the system confirmation flow. Deletion can
  propagate through iCloud Photos. Keep an independent backup before bulk cleanup.
- Duplicate matches are heuristic, auto-select non-keepers, and can be wrong.
  Review every proposed deletion; scanning is capped at 2,000 photos.
- The undocumented `PHAssetResource.fileSize` KVC lookup can break on future iOS
  versions. Returning zero does not protect against an Objective-C undefined-key
  exception. The estimate does not guarantee immediately reclaimed disk space.
- Upstream PR #3 reports multi-touch swipe reentrancy. This build retains upstream
  app behavior; avoid rapid repeated taps/swipes and review the queued deletions.
- Undo is incomplete: undoing an album action does not remove album membership,
  and undoing a favorite clears the flag rather than restoring its earlier value.

Only the build project metadata and build tooling were changed; app Swift sources
are the reviewed upstream sources. Actual compilation and device installation
must be confirmed separately by a successful Actions run and an on-device check.

## CI dependencies

No app dependency was added. The official GitHub Actions below are MIT licensed,
not archived, and pinned to complete commit hashes. Their v4 releases support
GitHub-hosted macOS runners; they perform checkout and artifact upload only.

| Repository | License | Latest main commit at review (UTC) | Version used |
| --- | --- | --- | --- |
| https://github.com/actions/checkout | MIT | 2026-07-20 | v4, `11d5960a326750d5838078e36cf38b85af677262` |
| https://github.com/actions/upload-artifact | MIT | 2026-10-07 | v4, `ea165f8d65b6e75b540449e92b4886f43607fa02` |

The workflow grants only `contents: read`, does not persist checkout credentials,
and runs only on manual requests or relevant pushes to the designated branches.
Official references: [Apple build settings](https://developer.apple.com/documentation/xcode/build-settings-reference),
[GitHub hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners),
[downloading artifacts](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts).
