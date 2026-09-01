<#
.SYNOPSIS
    Syncs the Kumo GitHub wiki into MkDocs-compatible docs/.
.DESCRIPTION
    Bare-clones the wiki and reads pages via `git show` rather than checking
    them out -- wiki page titles like "Broadcast Setup: Agent" become
    filenames with a literal colon, which NTFS can't create.

    Regenerates docs/*.md and mkdocs.yml from scratch on every run. The wiki
    is the source of truth; nothing in docs/ should be hand-edited.
#>

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

$WikiRepoUrl = "https://github.com/indiana-university/kumo.wiki.git"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$DocsDir = Join-Path $RepoRoot "docs"
$ImgSrc = Join-Path $RepoRoot "img"
$BrandingAssetsSrc = Join-Path $RepoRoot "branding\assets"
$CnameSrc = Join-Path $RepoRoot "branding\CNAME"

$SkipFiles = @("_Sidebar.md", "_Footer.md", "Home.md")

# Nav grouping is an editorial call, not something inferred from content --
# add new pages here as they're added to the wiki. Anything unmapped falls
# back to "Reference" with a warning rather than silently vanishing from nav.
$GroupOrder = @("Getting Started", "Setup", "Broadcast", "Reference")
$GroupBySlug = @{
    "kumo-in-a-nutshell"                         = "Getting Started"
    "kumo-cloud-storage-connector"                = "Getting Started"
    "service-plan"                                = "Getting Started"
    "portal-setup-onboarding"                     = "Setup"
    "access-broker-agent-setup"                   = "Setup"
    "portal-setup-storage-options"                = "Setup"
    "client-setup-windows"                        = "Setup"
    "client-setup-mac-os-x-no-longer-supported"   = "Setup"
    "broadcast-overview"                          = "Broadcast"
    "broadcast-setup-agent"                       = "Broadcast"
    "broadcast-setup-portal"                      = "Broadcast"
    "broadcast-usage"                             = "Broadcast"
    "troubleshooting"                             = "Reference"
    "diagrams"                                    = "Reference"
    "release-notes-client"                        = "Reference"
    "software-development-life-cycle"             = "Reference"
}

$BlobImgPattern = 'https://github\.com/indiana-university/kumo/(?:blob|raw)/[^/\s)]+/(img/[^\s)"''\]]+)'
$WikiLinkPattern = 'https://github\.com/indiana-university/kumo/wiki/([^\s)"''#\]]+)(#[^\s)"''\]]*)?'
$WikilinkPattern = '\[\[([^\]|]+?)(?:\|([^\]]+))?\]\]'

function Get-Slug([string]$Stem) {
    $slug = $Stem.Replace(":-", "-").Replace(":", "-").Replace(" ", "-")
    $slug = $slug -replace '[()]', ''
    $slug = $slug -replace '-{2,}', '-'
    return $slug.ToLowerInvariant()
}

function Invoke-GitIn([string]$WikiDir, [string[]]$Arguments) {
    $output = & git -C $WikiDir @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $output"
    }
    return ($output -join "`n")
}

function Get-WikiFiles([string]$WikiDir) {
    & git clone --bare --quiet $WikiRepoUrl $WikiDir 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to clone $WikiRepoUrl"
    }

    $names = (Invoke-GitIn $WikiDir @("ls-tree", "-r", "--name-only", "HEAD")) -split "`n" |
        Where-Object { $_ -like "*.md" }

    $files = @{}
    foreach ($name in $names) {
        $files[$name] = Invoke-GitIn $WikiDir @("show", "HEAD:$name")
    }
    return $files
}

function Get-SlugMap([hashtable]$Files) {
    $map = @{}
    foreach ($name in $Files.Keys) {
        if ($SkipFiles -contains $name) { continue }
        $stem = $name.Substring(0, $name.Length - 3)
        $map[$stem] = Get-Slug $stem
    }
    return $map
}

function Update-Links([string]$Text, [hashtable]$SlugByStem) {
    $Text = [regex]::Replace($Text, $BlobImgPattern, { param($m) $m.Groups[1].Value })

    $Text = [regex]::Replace($Text, $WikiLinkPattern, {
        param($m)
        $stem = $m.Groups[1].Value
        if ($SlugByStem.ContainsKey($stem)) {
            return "$($SlugByStem[$stem]).md$($m.Groups[2].Value)"
        }
        return $m.Value
    })

    $Text = [regex]::Replace($Text, $WikilinkPattern, {
        param($m)
        $display = $m.Groups[1].Value
        $target = if ($m.Groups[2].Success) { $m.Groups[2].Value } else { $display }
        $parts = $target -split '#', 2
        $stem = $parts[0]
        $anchor = if ($parts.Length -gt 1) { "#$($parts[1])" } else { "" }
        $slug = if ($SlugByStem.ContainsKey($stem)) { $SlugByStem[$stem] } else { Get-Slug $stem }
        return "[$display]($slug.md$anchor)"
    })

    return $Text
}

function Get-Nav([string]$HomeMd, [hashtable]$SlugByStem) {
    $orderedSlugs = [System.Collections.Generic.List[string]]::new()
    foreach ($stem in ($SlugByStem.Keys | Sort-Object)) {
        $pattern = "/wiki/" + [regex]::Escape($stem) + '(#|\)|$)'
        if ([regex]::IsMatch($HomeMd, $pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)) {
            if (-not $orderedSlugs.Contains($SlugByStem[$stem])) {
                $orderedSlugs.Add($SlugByStem[$stem])
            }
        }
    }
    $remaining = $SlugByStem.Values | Where-Object { -not $orderedSlugs.Contains($_) } | Sort-Object
    foreach ($slug in $remaining) {
        if ($slug -ne "contact-us") { $orderedSlugs.Add($slug) }
    }
    if ($SlugByStem.Values -contains "contact-us") { $orderedSlugs.Add("contact-us") }

    $slugToTitle = @{}
    foreach ($stem in $SlugByStem.Keys) {
        $title = (($stem -replace '[:\-]+', ' ') -replace '\s+', ' ').Trim()
        $slugToTitle[$SlugByStem[$stem]] = $title
    }

    $groups = [ordered]@{}
    foreach ($groupName in $GroupOrder) { $groups[$groupName] = [ordered]@{} }

    $nav = [ordered]@{ "Home" = "index.md" }
    foreach ($slug in $orderedSlugs) {
        if ($slug -eq "contact-us") { continue }
        $title = $slugToTitle[$slug]
        $group = if ($GroupBySlug.ContainsKey($slug)) { $GroupBySlug[$slug] } else {
            Write-Warning "No nav group mapped for '$slug' -- adding to Reference"
            "Reference"
        }
        $groups[$group][$title] = "$slug.md"
    }
    foreach ($groupName in $GroupOrder) {
        if ($groups[$groupName].Count -gt 0) {
            $nav[$groupName] = $groups[$groupName]
        }
    }
    if ($SlugByStem.Values -contains "contact-us") {
        $nav[$slugToTitle["contact-us"]] = "contact-us.md"
    }
    return $nav
}

function ConvertTo-NavYaml($Nav, [int]$Indent = 1) {
    $pad = "  " * $Indent
    $lines = foreach ($key in $Nav.Keys) {
        $value = $Nav[$key]
        if ($value -is [System.Collections.Specialized.OrderedDictionary]) {
            "$pad- `"$key`":"
            ConvertTo-NavYaml $value ($Indent + 1)
        }
        else {
            "$pad- `"$key`": $value"
        }
    }
    return $lines -join "`n"
}

function Write-MkDocsYml([System.Collections.Specialized.OrderedDictionary]$Nav) {
    $navLines = ConvertTo-NavYaml $Nav
    $year = (Get-Date).Year
    $yaml = @"
site_name: Kumo
site_url: https://kumo.iu.edu/
site_description: Documentation for Kumo, Indiana University's cloud storage connector.
repo_url: https://github.com/indiana-university/kumo
edit_uri: ""
copyright: "$year"

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
$navLines
"@
    [System.IO.File]::WriteAllText((Join-Path $RepoRoot "mkdocs.yml"), $yaml, $Utf8NoBom)
}

if (Test-Path $DocsDir) {
    Remove-Item -Path $DocsDir -Recurse -Force
}
New-Item -ItemType Directory -Path $DocsDir | Out-Null

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempDir | Out-Null
try {
    $files = Get-WikiFiles (Join-Path $tempDir "kumo.wiki.git")
} finally {
    Remove-Item -Path $tempDir -Recurse -Force
}

$slugByStem = Get-SlugMap $files

foreach ($name in $files.Keys) {
    if ($SkipFiles -contains $name) { continue }
    $slug = $slugByStem[$name.Substring(0, $name.Length - 3)]
    $content = Update-Links $files[$name] $slugByStem
    [System.IO.File]::WriteAllText((Join-Path $DocsDir "$slug.md"), $content, $Utf8NoBom)
}

$homeRaw = if ($files.ContainsKey("Home.md")) { $files["Home.md"] } else { "" }
[System.IO.File]::WriteAllText((Join-Path $DocsDir "index.md"), (Update-Links $homeRaw $slugByStem), $Utf8NoBom)

if (Test-Path $ImgSrc) { Copy-Item -Path $ImgSrc -Destination (Join-Path $DocsDir "img") -Recurse }
if (Test-Path $BrandingAssetsSrc) { Copy-Item -Path $BrandingAssetsSrc -Destination (Join-Path $DocsDir "assets") -Recurse }
if (Test-Path $CnameSrc) { Copy-Item -Path $CnameSrc -Destination (Join-Path $DocsDir "CNAME") }

Write-MkDocsYml (Get-Nav $homeRaw $slugByStem)

Write-Host "Synced $($slugByStem.Count) wiki pages into $DocsDir"
