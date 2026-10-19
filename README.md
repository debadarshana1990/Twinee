# Twinee

> **Everything is vibe-coded. I have no idea how this code runs — I’m a C guy.**
>
> It started as “I just need somewhere to put that thought,” and somehow became a knowledge garden, a task board, a diff tool, a code browser, a focus timer, a Git helper, and an app launcher. If a pointer escapes, please file a bug. If it doesn’t, let’s call it architecture.

## ⚠️ Warning: read this part, it's the important one

**This is a personal project and it is 100% AI-coded.** A human (me, a C programmer) had ideas and typed prompts; an AI wrote every line of Swift. I have not reviewed it like a real engineer would.

- Expect bugs, rough edges and the occasional "why did it do that?".
- **Back up your data** (`~/Library/Application Support/Twinee`). I take no responsibility for lost notes, lost tasks or lost dignity.
- The AI chat panel shells out to CLI tools you install yourself and sends the open page to the one you pick. Don't open secrets in there.
- No support, no roadmap promises, no SLA. If it breaks, you get to keep both pieces.

## What is this?

Twinee is a local-first Mac app that started as "somewhere to put a thought" and, through a series of increasingly ambitious prompts, now holds your notes, tasks, whiteboards, code, diffs and a focus timer. No account, no cloud, no subscription — just a SwiftUI app and a lot of sticky notes.

## Download and install

Grab **Twinee-3.0.0.dmg** from [Releases](https://github.com/debadarshana1990/Twinee/releases), open it, drag Twinee to Applications. Universal build: Apple silicon and Intel, macOS 13+.

It's **ad-hoc signed, not notarized** (Apple wants $99/year to be told I'm trustworthy). On first launch:

- macOS 15+: open it once, then **System Settings → Privacy & Security → Open Anyway**.
- macOS 13/14: Control-click → **Open**.
- Or: `xattr -dr com.apple.quarantine /Applications/Twinee.app`

Only do this if you trust where the download came from.

## What's inside

### 📝 Pages (Confluence-ish, not Notepad-ish)
- Projects with pages nested under them; rename and delete from the sidebar.
- Wiki layout: title, byline with word count, labels, link field, project/type pickers.
- Rich editor: H1–H3, bold/italic/underline, lists, links, syntax-highlighted code blocks (type ```` ``` ````).
- **Insert menu**: Info/Note/Success/Warning/Error panels, status tags, dividers.
- **On this page** outline, and a full-width toggle.
- **Sticky notes** (light red, blue or green): drag, resize, recolour.

### 🖍️ Whiteboards
A global one plus one per project. Pen, eraser, colours, width, undo.

### ✅ ToDo
Per-project **Bucket → Ongoing → Done** boards, plus an All-tasks view.

### 🔎 Code Browser
- **Open from Git**: paste a URL, choose a branch, browse — no repository to create.
- Any text file opens; C/C++/Python also get outline, symbols, go-to-definition and find-usages.
- HTML **Preview** (scripts disabled).
- **Notes on lines**, stored per repository.

### ✨ AI chat (⇧⌘I)
A side panel that reads the open page. Choose GitHub Copilot, Gemini, Claude or Codex; each runs through its own CLI, which you install and sign in to separately. The command for each is editable.

### 🛠️ Other apps
**Compare** (side-by-side diff), **Git Pull** (clone/pull), **Timer** (focus + stopwatch), **Launcher** (open your Mac apps).

### 🪟 Interface
Resizable sidebars, collapsible full-page mode (hover the left edge to peek), light/dark themes, and **Help ▸ Twinee Help** for the version number.

### Data and privacy
Nothing is uploaded or synced by Twinee itself. Data lives in `~/Library/Application Support/Twinee` (`workspace.json`, `devtools.json`, `whiteboards.json`). Remote Git browsing keeps throwaway shallow copies in `~/Library/Caches/Twinee`. Deleting the app does not delete your data.

## License

Twinee is released under the [MIT License](LICENSE). You may use, modify, and redistribute it, including commercially, while retaining the copyright and license notice.

## Build from source

Requirements: macOS 13 or later, Xcode Command Line Tools, and Swift 5.9 or newer. There are no third-party package dependencies.

From the repository root:

- `bash build-app.sh` builds a universal `dist/Twinee.app`, a drag-to-Applications `dist/Twinee-3.0.0.dmg`, and a ZIP archive.
- `VERSION=3.0.1 bash build-app.sh` sets the bundle version and artifact names.
- `swift run` builds and launches the app for development.
- `swift scripts/make-icon.swift` regenerates `Resources/AppIcon.icns`.

The build script compiles arm64 and x86_64 slices, assembles the `.app` bundle, ad-hoc signs it, creates the DMG and ZIP, and prints SHA-256 checksums. To sign with a Developer ID and notarize, configure an Apple Developer ID certificate and a `notarytool` Keychain profile, then run `SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=your-profile bash build-app.sh`.

## Release infrastructure

Pushing a version tag such as `v3.0.0` runs [the release workflow](.github/workflows/release.yml) on a macOS GitHub Actions runner. It builds the universal app and attaches the DMG and ZIP to a GitHub release using [RELEASE_NOTES.md](RELEASE_NOTES.md). To cut a release:

1. Build and verify the app locally with `bash build-app.sh`.
2. Commit the source, packaging script, icon, and workflow.
3. Create and push the tag: `git tag v3.0.0 && git push origin main v3.0.0`.
4. GitHub Actions builds the downloadable artifacts and publishes the release.

The automated GitHub build uses ad-hoc signing too, so it has the same first-launch Gatekeeper notice. The DMG/ZIP are generated by the workflow and attached to the release; they are not committed to the source repository.
