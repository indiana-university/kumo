# CLAUDE.md

Orients future Claude sessions in this repo.

## What this repo is

`indiana-university/kumo` — public repo whose main job today is hosting the Kumo wiki
(`kumo.wiki.git`, a separate git repo GitHub attaches to this one) and the `img/` files that
wiki pages embed. It's being turned into the source for a fully static, IU-branded
documentation + status site, hosted independently of Kumo Portal so it stays useful when
Portal itself is down. Kumo Portal's own rewrite lives in a separate repo,
`Kumo-Server-Blazor` (not this one) — see that repo's CLAUDE.md for the Portal/AccessBroker/
Client architecture if this work needs to reference it.

**This repo is public.** Anything with internal detail (hostnames, cluster/project names,
credentials) does not belong here.

## Current state (as of this handoff)

Done and verified:
- `scripts/sync_wiki.ps1` — bare-clones `kumo.wiki.git` and regenerates `docs/` + `mkdocs.yml`
  from the wiki's markdown on every run. The wiki is the single source of truth; nothing in
  `docs/` or `mkdocs.yml` should be hand-edited (both are gitignored, build artifacts). Written
  in PowerShell rather than Python since that's what the team already uses elsewhere — MkDocs
  itself is still a Python tool, but it's depended on as-is, not something anyone needs to read
  or write Python to maintain.
- `branding/assets/iu-theme.css` — placeholder IU crimson theme for mkdocs-material.
  **Not verified against IU's actual brand toolkit (brand.iu.edu)** — flagged in the file, do
  this before launch.
- Ran the sync against the live wiki (17 pages), built with `mkdocs build --strict` (clean),
  served and browser-tested it — nav, search, and images all resolved correctly.
- Confirmed `https://servicenow.iu.edu/api/iuit/status/notices` sends
  `Access-Control-Allow-Origin: *` — a static page's own JS can fetch it directly, no
  server-side proxy needed. This is what the legacy Portal's `StatusController` used to proxy
  server-side; that pattern is obsolete for this rewrite.

Not started yet:
- The status page itself (HTML/JS calling the ServiceNow endpoint above, rendering
  Maintenance/Ongoing/Alert notices for the "IU Cloud Storage" service — service id
  `3461ae821b9df8908b3999fabc4bcba7`, number `BSN0001274` in prod).
- A `/health` endpoint on Kumo Portal (doesn't exist yet in `Kumo.Portal/Program.cs` in the
  Blazor rewrite repo) with CORS opened for this site's origin, so the status page can also
  show live Portal up/down — client-side, no backend needed here either once that exists.
- GitHub Actions workflow to run the sync + `mkdocs build` + deploy on a schedule (wiki edits
  aren't webhook-visible from a public repo workflow by default, so this will likely poll on a
  cron rather than react instantly).
- DNS cutover: `kumo.iu.edu` currently redirects to the GitHub wiki; needs to point at GitHub
  Pages instead once this site is ready (CNAME file + DNS change, coordinate with IU
  networking).

## Key decisions made, and why

- **GitHub Pages, not IU's Harbor/K8s.** Originally scoped as a container on IU's internal
  K8s (deployed via Harbor + Azure DevOps, which the team already uses for other services) so
  a live-health-check backend could run server-side. Once the ServiceNow CORS check above came
  back open, and given the "contact form" turned out to just be `mailto:` links (see
  `docs/contact-us.md`), the whole site — docs and status both — has zero backend
  requirement. GitHub Pages is simpler to run (no container/pipeline/cluster to maintain) and,
  more importantly, is hosted entirely outside IU's own infra — which matters because the
  entire point of this project is surviving an IU-side outage, not just a Portal outage.
- **MkDocs + mkdocs-material**, not Docusaurus/Hugo/Jekyll — plain markdown in, minimal config,
  built-in search, easy IU theme override via `extra_css`.
- **Auto-sync from the wiki, not a one-time import.** The wiki stays the editorial source of
  truth; this repo is a presentation layer regenerated from it, so the two never drift apart.
- **PowerShell for `sync_wiki`, not Python**, even though the site's build tool (MkDocs) is
  Python. A reviewer flagged that requiring Python knowledge to maintain the one piece of
  custom logic in this repo was a real barrier for a team that otherwise works in .NET/
  PowerShell; ported it so nobody has to learn a new language just to touch nav ordering or
  link rewriting.

## Gotchas hit — read before repeating the debugging

1. **GitHub wiki page titles become filenames with literal colons** (e.g.
   `Broadcast-Setup:-Agent.md`), which NTFS can't create. A normal `git clone` of
   `kumo.wiki.git` fails on Windows with "invalid path" / "unable to checkout working tree".
   Fix: clone `--bare` and read files via `git show HEAD:<path>` — never check the wiki repo
   out to a working tree. `sync_wiki.ps1` already does this.
2. **`[[Display|Target#anchor]]` wikilinks need the anchor split off before slugifying the
   target**, or you get mangled links like `page#anchor.md` instead of `page.md#anchor`. Fixed
   in `sync_wiki.ps1`'s `Update-Links` — if touching that again, re-verify against
   `service-plan.md`'s Box/Dropbox/Google Drive links after rebuilding.
3. **YAML nav titles can't contain raw colons** — several wiki page names do (e.g. "Client
   Setup: Windows"). `sync_wiki.ps1` strips `:`/`-` into spaces for display titles and quotes
   every nav entry defensively.
4. **PowerShell hashtables don't preserve enumeration order** (unlike Python dicts), and .NET's
   default string hashing is randomized per process — so building the nav by iterating a
   hashtable's `.Keys` produces a different, shuffling order on every run. `Get-Nav` explicitly
   `Sort-Object`s the stems before iterating; if the nav order ever looks random from one build
   to the next, this is why.
5. **`git show` output needs explicit UTF-8 handling** — a wiki page hit encoding issues on
   Windows without it. Fixed by setting `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8`
   at the top of `sync_wiki.ps1`, and writing output files via `[System.IO.File]::WriteAllText`
   with an explicit no-BOM UTF-8 encoding rather than PowerShell's `Set-Content` (which defaults
   to UTF-8 *with* BOM on Windows PowerShell).
6. **A few links in the *source wiki content itself* are already broken** (not sync-script
   bugs): `Client-Setup:-Mac-OS-X` links to a `###domain-membership` anchor that doesn't exist,
   `Troubleshooting` links to a stale `client-setup-windows#with-uac-enabled` anchor, and two
   OneDrive anchors are case-mismatched (`#OneDrive` vs generated `#onedrive`). Worth a wiki
   content cleanup pass at some point; not something the sync script should silently paper
   over.
7. **Python on this dev machine** (still needed for MkDocs itself, just not for the sync
   script anymore): `python`/`py` aren't on the plain Bash/git-bash PATH: use the full path
   `C:\Python311\python.exe`, or PowerShell's `py` launcher. `pip install --user` was needed to
   sidestep a locked `watchmedo.exe` from a prior partial install.

## Local dev

```powershell
pwsh scripts\sync_wiki.ps1                        # regenerate docs/ + mkdocs.yml from the wiki
C:\Python311\python.exe -m mkdocs serve           # preview at http://127.0.0.1:8000
C:\Python311\python.exe -m mkdocs build --strict  # verify before shipping
```
