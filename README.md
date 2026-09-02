# Kumo Help

Welcome! Kumo documentation can be found in the [wiki](https://github.com/indiana-university/kumo/wiki). Please contact kumo@iu.edu if you have any questions that can't be resolved here.

## About this repo

This repo builds a static, IU-branded docs site (and eventually a status page) from
that wiki, published to GitHub Pages so it stays reachable even when Kumo Portal is
down. It's a presentation layer, not a second copy of the content -- **the wiki is
still where you edit docs.** Nothing here needs to change when the wiki changes.

**There are no content files in this repo.** `docs/` and `mkdocs.yml` -- what MkDocs
actually builds from -- are generated on every build by [`scripts/sync_wiki.ps1`](scripts/sync_wiki.ps1),
which pulls the current wiki content fresh each time. Both are gitignored: they never
get committed, and hand-editing them locally is pointless since the next sync
overwrites them. If you want to change site *content*, edit the wiki. If you want to
change site *structure or behavior* (nav ordering, link rewriting, branding), edit
`scripts/sync_wiki.ps1` or the files below.

What's actually committed here, and what each does:

| Path | Purpose |
| --- | --- |
| [`scripts/sync_wiki.ps1`](scripts/sync_wiki.ps1) | Generates `docs/` + `mkdocs.yml` from the wiki. The only place nav structure and wiki-link rewriting logic live. |
| [`branding/`](branding/) | IU theme CSS, the trident logo SVG, and the `CNAME` file for the custom domain -- copied into the generated `docs/` on every sync. |
| [`overrides/`](overrides/) | mkdocs-material theme template overrides (currently just the IU-branded footer). |
| [`.github/workflows/`](.github/workflows/) | `check-docs.yml` builds (no deploy) on every PR; `deploy-docs.yml` builds and publishes to GitHub Pages on merge to `master`, on a schedule, and on demand. |

**Why a schedule, not just "on wiki edit"?** GitHub wikis don't trigger Actions
workflows in the parent repo when edited, so `deploy-docs.yml` polls hourly to pick
up wiki changes, in addition to running immediately when the sync script or branding
changes.

**Live site**: `kumo.iu.edu` once DNS is cut over (not done yet). Until then, once
this is merged and GitHub Pages is enabled, the interim URL is
`https://indiana-university.github.io/kumo/`.

**Preview locally** before pushing:

```powershell
pwsh scripts/sync_wiki.ps1   # regenerate docs/ + mkdocs.yml from the current wiki
python -m mkdocs serve       # preview at http://127.0.0.1:8000, live-reloads on changes
```

The sync script is PowerShell -- that's the only custom logic in this repo, and
PowerShell is what the team already uses elsewhere. MkDocs itself (the second
command) is a third-party Python tool we depend on as-is, same as any other
package; nobody needs to read or write Python to maintain this site.

See [`CLAUDE.md`](CLAUDE.md) for the fuller history of decisions and gotchas hit
building this.
