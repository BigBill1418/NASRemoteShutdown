# Documentation Discipline (MANDATORY)

Any code change, feature change, or forward-looking plan MUST be recorded in a logical place in this repo as part of the same change. The goal: any future session can pick up exactly where the last one left off.

- **Code/feature changes** → update `CHANGELOG.md` (or equivalent) with date + summary.
- **Future plans / roadmap items** → add to `ROADMAP.md`, `docs/plans/`, or an ADR under `docs/adr/`.
- **Non-obvious decisions** → record as an ADR (`docs/adr/NNNN-title.md`).
- **Progress on in-flight work** → update `PROGRESS.md` or the relevant plan doc.

No undocumented changes. If a repo lacks the right file, create it. Commit the docs alongside the code — never in a separate follow-up that might get forgotten.
