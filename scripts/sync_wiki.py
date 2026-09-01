#!/usr/bin/env python3
"""Sync the Kumo GitHub wiki into MkDocs-compatible docs/.

The wiki is cloned as a bare repo and read via `git show`, never checked
out to a working tree -- GitHub wiki page titles like "Broadcast Setup:
Agent" become filenames with a literal colon, which is invalid on NTFS
and breaks a normal `git clone` on Windows.

Regenerates docs/*.md and mkdocs.yml from scratch on every run, so the
wiki stays the single source of truth. Do not hand-edit files in docs/.
"""
import datetime
import pathlib
import re
import shutil
import subprocess
import tempfile

WIKI_REPO_URL = "https://github.com/indiana-university/kumo.wiki.git"
REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS_DIR = REPO_ROOT / "docs"
IMG_SRC = REPO_ROOT / "img"
IMG_DEST = DOCS_DIR / "img"
BRANDING_ASSETS_SRC = REPO_ROOT / "branding" / "assets"
BRANDING_ASSETS_DEST = DOCS_DIR / "assets"
CNAME_SRC = REPO_ROOT / "branding" / "CNAME"
CNAME_DEST = DOCS_DIR / "CNAME"

SKIP_FILES = {"_Sidebar.md", "_Footer.md", "Home.md"}

BLOB_IMG_RE = re.compile(
    r"https://github\.com/indiana-university/kumo/(?:blob|raw)/[^/\s)]+/(img/[^\s)\"'\]]+)"
)
WIKI_LINK_RE = re.compile(
    r"https://github\.com/indiana-university/kumo/wiki/([^\s)\"'#\]]+)(#[^\s)\"'\]]*)?"
)
WIKILINK_RE = re.compile(r"\[\[([^\]|]+?)(?:\|([^\]]+))?\]\]")


def git(*args: str, cwd: pathlib.Path) -> str:
    result = subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True)
    return result.stdout.decode("utf-8", errors="replace")


def slugify(stem: str) -> str:
    """GitHub wiki filename stem -> filesystem/URL-safe slug."""
    slug = stem.replace(":-", "-").replace(":", "-").replace(" ", "-")
    slug = re.sub(r"[()]", "", slug)
    slug = re.sub(r"-{2,}", "-", slug)
    return slug.lower()


def fetch_wiki_files(wiki_dir: pathlib.Path) -> dict[str, str]:
    """Bare-clone the wiki and return {filename: raw markdown} for every page."""
    subprocess.run(
        ["git", "clone", "--bare", "--quiet", WIKI_REPO_URL, str(wiki_dir)],
        check=True,
    )
    names = [n for n in git("ls-tree", "-r", "--name-only", "HEAD", cwd=wiki_dir).splitlines() if n]
    return {
        name: git("show", f"HEAD:{name}", cwd=wiki_dir)
        for name in names
        if name.endswith(".md")
    }


def build_slug_map(files: dict[str, str]) -> dict[str, str]:
    return {name[:-3]: slugify(name[:-3]) for name in files if name not in SKIP_FILES}


def rewrite_links(text: str, slug_by_stem: dict[str, str]) -> str:
    def wiki_link(m: re.Match) -> str:
        stem, anchor = m.group(1), m.group(2) or ""
        slug = slug_by_stem.get(stem)
        return f"{slug}.md{anchor}" if slug else m.group(0)

    def wikilink(m: re.Match) -> str:
        display, target = m.group(1), m.group(2) or m.group(1)
        stem, _, anchor = target.partition("#")
        slug = slug_by_stem.get(stem, slugify(stem))
        return f"[{display}]({slug}.md{'#' + anchor if anchor else ''})"

    text = BLOB_IMG_RE.sub(lambda m: m.group(1), text)
    text = WIKI_LINK_RE.sub(wiki_link, text)
    text = WIKILINK_RE.sub(wikilink, text)
    return text


def build_nav(home_md: str, slug_by_stem: dict[str, str]) -> list[tuple[str, str]]:
    """Preserve Home.md's listed reading order, then append anything left over."""
    ordered_slugs: list[str] = []
    for stem, slug in slug_by_stem.items():
        if re.search(rf"/wiki/{re.escape(stem)}(#|\)|$)", home_md, re.MULTILINE):
            if slug not in ordered_slugs:
                ordered_slugs.append(slug)
    remaining = sorted(
        slug for slug in slug_by_stem.values() if slug not in ordered_slugs
    )
    for slug in remaining:
        if slug != "contact-us":
            ordered_slugs.append(slug)
    if "contact-us" in slug_by_stem.values():
        ordered_slugs.append("contact-us")

    def titleize(stem: str) -> str:
        return re.sub(r"\s+", " ", re.sub(r"[:\-]+", " ", stem)).strip()

    slug_to_title = {v: titleize(k) for k, v in slug_by_stem.items()}
    return [("Home", "index.md")] + [
        (slug_to_title[slug], f"{slug}.md") for slug in ordered_slugs
    ]


def write_mkdocs_yml(nav: list[tuple[str, str]]) -> None:
    nav_lines = "\n".join(f'  - "{title}": {path}' for title, path in nav)
    year = datetime.date.today().year
    (REPO_ROOT / "mkdocs.yml").write_text(
        f"""site_name: Kumo
site_url: https://kumo.iu.edu/
site_description: Documentation for Kumo, Indiana University's cloud storage connector.
repo_url: https://github.com/indiana-university/kumo
edit_uri: ""
copyright: "{year}"

theme:
  name: material
  custom_dir: overrides
  logo: assets/iu-trident.svg
  palette:
    primary: custom
    accent: custom
  features:
    - navigation.tabs
    - navigation.top
    - search.suggest
extra_css:
  - assets/iu-theme.css

nav:
{nav_lines}
""",
        encoding="utf-8",
    )


def main() -> None:
    if DOCS_DIR.exists():
        shutil.rmtree(DOCS_DIR)
    DOCS_DIR.mkdir(parents=True)

    with tempfile.TemporaryDirectory() as tmp:
        wiki_dir = pathlib.Path(tmp) / "kumo.wiki.git"
        files = fetch_wiki_files(wiki_dir)

    slug_by_stem = build_slug_map(files)

    for name, raw in files.items():
        if name in SKIP_FILES:
            continue
        slug = slug_by_stem[name[:-3]]
        (DOCS_DIR / f"{slug}.md").write_text(rewrite_links(raw, slug_by_stem), encoding="utf-8")

    home_raw = files.get("Home.md", "")
    (DOCS_DIR / "index.md").write_text(rewrite_links(home_raw, slug_by_stem), encoding="utf-8")

    if IMG_SRC.exists():
        shutil.copytree(IMG_SRC, IMG_DEST)
    if BRANDING_ASSETS_SRC.exists():
        shutil.copytree(BRANDING_ASSETS_SRC, BRANDING_ASSETS_DEST)
    if CNAME_SRC.exists():
        shutil.copy(CNAME_SRC, CNAME_DEST)

    write_mkdocs_yml(build_nav(home_raw, slug_by_stem))
    print(f"Synced {len(slug_by_stem)} wiki pages into {DOCS_DIR}")


if __name__ == "__main__":
    main()
