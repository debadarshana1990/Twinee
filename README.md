# Twinee

> **Everything is vibe-coded. I have no idea how this code runs — I’m a C guy.**
>
> It started as “I just need somewhere to put that thought,” and somehow became a knowledge garden, a task board, a diff tool, a code browser, a focus timer, a Git helper, and an app launcher. If a pointer escapes, please file a bug. If it doesn’t, let’s call it architecture.

Twinee is a standalone, local-first Mac app for notes and developer tools. Keep projects, free-form pages, tasks, source code, repositories, links, and focus sessions in one place—without an account or a cloud service.

**This is the 1.0.0 release candidate.** It was built for one C programmer’s workflow, so expect rough edges and please keep backups of important data.

## Download and install

Download **Twinee-1.0.0.dmg** from the [GitHub Releases](https://github.com/debadarshana1990/Twinee/releases) page. Open the disk image, then drag Twinee to Applications. The universal app runs natively on Apple silicon and Intel Macs with macOS 13 or later.

This build is **ad-hoc signed, not Apple-notarized**. macOS may block the first launch because it cannot verify the developer:

- On macOS 15 or later, try opening Twinee once, then go to **System Settings → Privacy & Security → Open Anyway**.
- On macOS 13 or 14, Control-click Twinee in Applications and choose **Open**.
- Alternatively, remove the download quarantine with `xattr -dr com.apple.quarantine /Applications/Twinee.app`.

Only bypass Gatekeeper if you trust the source of the download. A Developer ID signed and notarized release is not set up yet.

## What’s inside

### Projects, topics, and writing

- Organize ideas into projects, with topics nested directly under each project.
- Write in a free-flow document editor: headings H1–H3, bold, italic, underline, bullets, numbered lists, links, and inline or fenced code blocks.
- Add code blocks with the toolbar or type `` ``` `` and press Return. Syntax colors follow a selected or detected programming language.
- Pages autosave locally; use **⌘S** to save immediately.
- Choose White or Black appearance.

### ToDo

- Each project opens on its own **Bucket → Ongoing → Done** task board.
- **All tasks** combines the projects. Add task notes, drag tasks between columns, or use the task controls to move and delete them.
- Project notes provide extra free-form writing space.

### Developer apps

- **Compare:** side-by-side text or file comparison, syntax highlighting, intra-line changes, whitespace/case options, hunk navigation, and copy-a-change-to-either-side controls.
- **Code Browser:** browse C, C++, and Python folders; inspect highlighted source with line numbers; browse file outlines and project symbols; jump to definitions; find usages.
- **Git Pull:** clone a remote repository to a folder you choose, pull saved repositories, or add an existing local repository. Cloning and pulling are included; pushing changes is not.
- **Timer:** focus/break timer and stopwatch, with project labels and session history.
- **Launcher:** add or drop `.app` bundles to open Mac applications from Twinee or its sidebar.

### Data and privacy

Twinee does not upload or sync your content. Workspace data is stored at `~/Library/Application Support/Twinee/workspace.json`; developer-app settings and history are stored alongside it in `devtools.json`. Back up this folder yourself. Removing the app does not remove your saved data.

## License

Twinee is released under the [MIT License](LICENSE). You may use, modify, and redistribute it, including commercially, while retaining the copyright and license notice.

## Build from source

Requirements: macOS 13 or later, Xcode Command Line Tools, and Swift 5.9 or newer. There are no third-party package dependencies.

From the repository root:

- `bash build-app.sh` builds a universal `dist/Twinee.app`, a drag-to-Applications `dist/Twinee-1.0.0.dmg`, and a ZIP archive.
- `VERSION=1.2.0 bash build-app.sh` sets the bundle version and artifact names.
- `swift run` builds and launches the app for development.
- `swift scripts/make-icon.swift` regenerates `Resources/AppIcon.icns`.

The build script compiles arm64 and x86_64 slices, assembles the `.app` bundle, ad-hoc signs it, creates the DMG and ZIP, and prints SHA-256 checksums. To sign with a Developer ID and notarize, configure an Apple Developer ID certificate and a `notarytool` Keychain profile, then run `SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=your-profile bash build-app.sh`.

## Release infrastructure

Pushing a version tag such as `v1.0.0` runs [the release workflow](.github/workflows/release.yml) on a macOS GitHub Actions runner. It builds the universal app and attaches the DMG and ZIP to a GitHub prerelease. To cut the 1.0.0 release candidate:

1. Build and verify the app locally with `bash build-app.sh`.
2. Commit the source, packaging script, icon, and workflow.
3. Create and push the tag: `git tag v1.0.0 && git push origin main v1.0.0`.
4. GitHub Actions builds the downloadable artifacts and publishes the prerelease.

The automated GitHub build uses ad-hoc signing too, so it has the same first-launch Gatekeeper notice. The DMG/ZIP are generated by the workflow and attached to the release; they are not committed to the source repository.
