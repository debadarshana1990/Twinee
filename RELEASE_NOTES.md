## ⚠️ Please read before you click anything

**Twinee is a personal project, and every line of it was written by AI.** I steer, the AI types, and nobody — including me — has reviewed it the way a grown-up engineer would. I'm a C programmer; this is Swift; we are both guessing.

- It may have bugs, rough edges, or opinions.
- Keep backups of anything you care about (`~/Library/Application Support/Twinee`).
- The AI chat panel runs command-line tools *you* install (Copilot, Gemini, Claude, Codex). Twinee does not ship with any of them, and the page you're reading is sent to whichever one you pick.
- No warranty, no support contract, no pager. MIT licensed.

---

# Twinee 4.0.0 — "TableSpoon: a study app that fits in a spoon"

3.0.0 had Projects. 4.0.0 asked: *what if Projects, but for people who actually want to learn something?* 🥄

### 🍴 TableSpoon replaces Projects
Study "C++ Memory Management", split it into subtopics, split *those* into sub-subtopics, and keep going until you have a folder tree deeper than your understanding of `free()`.
- **Topics and subtopics, nested forever.** Right-click → "New subtopic inside…".
- **Confluence-style pages** for notes and journal entries: headings, panels, status tags, an outline. Not Markdown. Old Markdown notes migrate on their own.
- **Code files with an editor**: syntax highlighting, line numbers, auto-indent, Cmd-click go-to-definition, find usages.
- **A real terminal** running *your* login shell, so Build & Run (⌘↵) uses whatever compiler *you* installed. Segfaults are now first-class study material.
- **Optional Whiteboard and ToDo per topic and subtopic.** Add one only if you want it; no board shaming.
- **Bookmarks and tags.** Star a page and it floats to the top of the sidebar. Tag it `#pointers`, search `#pointers`, find your pointers. Pointers: found.

### 🧹 Cleaned up
- Projects, Pages and Sticky Notes are gone. They had a good run.
- ToDo and Whiteboard are now global boards, plus the per-topic ones above.
- Twinee opens straight on TableSpoon.
- Existing workspaces still load; nothing of yours gets deleted.

### 🙏 Third-party
Terminal emulation by [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT).

---

## Install

1. Download **Twinee-4.0.0.dmg** below, open it, drag Twinee to Applications.
2. The app is **ad-hoc signed, not notarized**, so macOS will frown at it. Control-click → **Open**, or on macOS 15+ use **System Settings → Privacy & Security → Open Anyway**, or run `xattr -dr com.apple.quarantine /Applications/Twinee.app`.
3. Only do that if you trust the source. Reading the warnings above counts as due diligence.

Universal binary (Apple silicon + Intel), macOS 13+.

**Known honest limitations:** AI features need a separately installed CLI; private HTTPS repos can't prompt for credentials; I have not personally audited the code, and neither has the AI.
