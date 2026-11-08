<#
.SYNOPSIS
Publishes a PBI Builder release to the one permanent GitHub repository (ArunGuruswamy/PBI, branch main).

.DESCRIPTION
Every version goes to the same repository as tag v<version> (v5.7.0, v5.7.1, v5.8.0, ...). This script never creates a
repository, never force-pushes and never rewrites history; git itself refuses a push that is not a fast-forward.
 1. Verify: a clean work tree on -Branch; the version (core.js VERSION) has a CHANGELOG section; the permanent repository's
    branch is an ancestor of HEAD (merge it first otherwise); tag v<version> is unused or already points at HEAD.
 2. Test: build the HTML, check the scripts, run every maintainer test (test-*.cjs).
 3. Build: node release.cjs (package root files and releases/<name>/<name>.zip + .sha256, extracted and checked with
    Expand-Archive), then recheck every SHA256SUMS.txt line and the ZIP checksum.
 4. Commit "release: Akzo SDD PBI Builder v<version>" and the annotated tag v<version>.
 5. Push the branch and the tag.
 6. Create the GitHub release with the CHANGELOG section as its notes and upload the ZIP and its .sha256.
 7. Verify the remote branch and tag point at the release commit and every asset downloads with its SHA-256.
A rerun after a failure resumes from the tag: a tag already on HEAD skips steps 2-4, and only missing assets are uploaded.
Needs git, Node 20+ and Windows PowerShell 5.1. git push uses your normal git credentials; the release API needs a token
with write access to the repository in GITHUB_TOKEN or GH_TOKEN (not needed for -DryRun).

.EXAMPLE
$env:GITHUB_TOKEN = '<token>'; .\maintainer\Publish-Release.ps1
.EXAMPLE
.\maintainer\Publish-Release.ps1 -DryRun
(Steps 1-3 only; the build outputs are removed again and nothing is committed or pushed.)
#>
[CmdletBinding()]
param(
    [string]$Repository = 'ArunGuruswamy/PBI',
    [string]$Branch = 'main',
    [switch]$DryRun,
    # Appended to the release commit message, for example a Co-Authored-By line.
    [string]$Trailer
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$maintainer = $PSScriptRoot; $root = Split-Path -Parent $maintainer
function Step([string]$m) { Write-Host ''; Write-Host "== $m" }
# Windows PowerShell 5.1 turns a native command's stderr into errors under 'Stop'; git reports progress there.
function Invoke-Git {
    $ErrorActionPreference = 'Continue'
    $out = @(& git -C $root @args 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed (exit $LASTEXITCODE): $($out -join ' ')" }
    return , $out
}
function Invoke-Node([string[]]$arguments) {
    Push-Location $maintainer
    try { & node @arguments; if ($LASTEXITCODE -ne 0) { throw "node $($arguments -join ' ') failed (exit $LASTEXITCODE)." } } finally { Pop-Location }
}
function Get-Sha256([string]$path) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
# The peeled commit of a tag on the remote (annotated tags list ^{}), or $null.
function Get-RemoteTagCommit([string]$remote, [string]$tag) {
    $lines = Invoke-Git ls-remote $remote "refs/tags/$tag" "refs/tags/$tag^{}"
    $peeled = @($lines | Where-Object { $_ -match "refs/tags/$([regex]::Escape($tag))\^\{\}$" }); $plain = @($lines | Where-Object { $_ -match "refs/tags/$([regex]::Escape($tag))$" })
    if ($peeled.Count) { return ($peeled[0] -split '\s+')[0] }; if ($plain.Count) { return ($plain[0] -split '\s+')[0] }; return $null
}
function Invoke-GitHub([string]$method, [string]$uri, $body, [byte[]]$bytes, [string]$contentType = 'application/json') {
    $headers = @{ Authorization = "Bearer $token"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28'; 'User-Agent' = 'akzo-pbi-builder-publish' }
    if ($null -ne $bytes) { return Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -ContentType $contentType -Body $bytes }
    if ($null -ne $body) { return Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $body -Depth 5))) }
    return Invoke-RestMethod -Method $method -Uri $uri -Headers $headers
}
function Get-Release([string]$tag) {
    try { return Invoke-GitHub GET "https://api.github.com/repos/$Repository/releases/tags/$tag" }
    catch { if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { return $null }; throw }
}

# ---- 1. Verify the local source, the history and the permanent repository ----
Step 'Verify local source and history'
$version = (& node -p "require(process.argv[1]).VERSION" (Join-Path $maintainer 'src\core.js')).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "core.js VERSION '$version' is not a version number." }
$tag = "v$version"; $name = "Akzo-SDD-PBI-Builder-$version"
$current = (Invoke-Git rev-parse --abbrev-ref HEAD)[0]
if ($current -cne $Branch) { throw "Check out $Branch first (current branch: $current)." }
$dirty = Invoke-Git status --porcelain
if ($dirty.Count) { throw "The work tree has uncommitted changes; commit or stash them first:`n$($dirty -join "`n")" }
$changelog = [System.IO.File]::ReadAllText((Join-Path $root 'CHANGELOG.md'), [System.Text.Encoding]::UTF8)
$section = [regex]::Match($changelog, "(?ms)^## $([regex]::Escape($version))\b.*?(?=^## |\z)")
if (-not $section.Success) { throw "CHANGELOG.md has no '## $version' section for the release notes." }
$notes = $section.Value.Trim()
$url = "https://github.com/$Repository.git"; $remote = $null
foreach ($r in (Invoke-Git remote)) { if (((Invoke-Git remote get-url $r)[0] -replace '\.git$', '') -ieq ($url -replace '\.git$', '')) { $remote = $r; break } }
if (-not $remote) { $remote = 'pbi'; [void](Invoke-Git remote add $remote $url); Write-Host "Added remote '$remote' for $url." }
[void](Invoke-Git fetch $remote $Branch --tags)
$head = (Invoke-Git rev-parse HEAD)[0]; $remoteHead = (Invoke-Git rev-parse "refs/remotes/$remote/$Branch")[0]
$ErrorActionPreference = 'Continue'; & git -C $root merge-base --is-ancestor $remoteHead $head; $ancestor = $LASTEXITCODE -eq 0; $ErrorActionPreference = 'Stop'
if (-not $ancestor) { throw "$Repository $Branch ($remoteHead) has commits that HEAD lacks. Merge $remote/$Branch first; this script never force-pushes." }
$ahead = (Invoke-Git rev-list --count "$remoteHead..$head")[0]
Write-Host "Version $version, tag $tag. HEAD $head is $ahead commit(s) ahead of $remote/$Branch ($remoteHead)."
$remoteTag = Get-RemoteTagCommit $remote $tag
$localTag = $null; $ErrorActionPreference = 'Continue'; $t = & git -C $root rev-parse -q --verify "refs/tags/$tag^{commit}" 2>$null; if ($LASTEXITCODE -eq 0) { $localTag = "$t".Trim() }; $ErrorActionPreference = 'Stop'
foreach ($found in @($remoteTag, $localTag)) { if ($found -and $found -cne $head) { throw "Tag $tag already exists for $found, not HEAD. Every release needs a new version; nothing was changed." } }
$resume = [bool]($remoteTag -or $localTag)
if ($resume) { Write-Host "Tag $tag already points at HEAD: resuming the publication." }
$token = $env:GITHUB_TOKEN; if (-not $token) { $token = $env:GH_TOKEN }
if ($token) {
    $repo = Invoke-GitHub GET "https://api.github.com/repos/$Repository"
    if (-not $repo.permissions.push) { throw "The token in GITHUB_TOKEN/GH_TOKEN cannot write to $Repository." }
} elseif (-not $DryRun) { throw 'Set GITHUB_TOKEN (or GH_TOKEN) to a token with write access to the repository; the GitHub release API needs it. Nothing was changed.' }

$zipDir = Join-Path $root "releases\$name"; $zip = Join-Path $zipDir "$name.zip"; $zipSum = "$zip.sha256"
if (-not $resume) {
    # ---- 2. Regression tests ----
    Step 'Run the regression tests'
    Invoke-Node @('build.cjs'); Invoke-Node @('--check', 'src/core.js'); Invoke-Node @('--check', 'src/ui.js')
    $tests = @(Get-ChildItem -LiteralPath $maintainer -Filter 'test-*.cjs' | Sort-Object Name)
    $runner = @($tests | Where-Object { [System.IO.File]::ReadAllText($_.FullName).Contains("require('node:test')") } | ForEach-Object { $_.Name })
    foreach ($t in @($tests | Where-Object { $runner -notcontains $_.Name })) { Write-Host "-- $($t.Name)"; Invoke-Node @($t.Name) }
    Write-Host "-- node --test $($runner -join ' ')"; Invoke-Node (@('--test') + $runner)
    Write-Host 'test-gui.ps1 drives the setup window on an interactive desktop and is not run here.'

    # ---- 3. Release artifacts and checksums ----
    Step 'Build and verify the release artifacts'
    Invoke-Node @('release.cjs')
}
foreach ($f in @($zip, $zipSum, (Join-Path $root 'SHA256SUMS.txt'))) { if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "Missing release artifact: $f" } }
$expected = ([System.IO.File]::ReadAllText($zipSum) -split '\s+')[0]
if ((Get-Sha256 $zip) -cne $expected) { throw "$name.zip does not match $name.zip.sha256." }
$checked = 0
foreach ($line in [System.IO.File]::ReadAllLines((Join-Path $root 'SHA256SUMS.txt'))) {
    if (-not $line.Trim()) { continue }
    $hash, $rel = $line -split '  ', 2
    if ((Get-Sha256 (Join-Path $root $rel)) -cne $hash) { throw "SHA256SUMS.txt does not match $rel." }; $checked++
}
Write-Host "Checksums verified: $name.zip ($expected) and $checked package files in SHA256SUMS.txt."
if (-not $resume) {
    # Only the package files release.cjs writes may have changed.
    $allowed = '^(Akzo-SDD-PBI-Builder\.html|pbi-builder-bundle\.json|SHA256SUMS\.txt|(Install|Uninstall)(-PBIBuilder)?\.(cmd|ps1)|PBI-Builder-Setup\.ps1|releases/)'
    $unexpected = @((Invoke-Git status --porcelain --untracked-files=all) | Where-Object { $_.Substring(3) -notmatch $allowed })
    if ($unexpected.Count) { throw "Unexpected changes after the build:`n$($unexpected -join "`n")" }
}
if ($DryRun) {
    if (-not $resume) {
        [void](Invoke-Git checkout -- .)
        if (-not (Invoke-Git ls-files -- "releases/$name").Count) { Remove-Item -LiteralPath $zipDir -Recurse -Force }
    }
    Write-Host ''; Write-Host "Dry run complete: $tag is ready to publish to $Repository $Branch. Nothing was committed or pushed."
    exit 0
}

# ---- 4. Release commit and tag ----
if (-not $resume) {
    Step "Commit and tag $tag"
    [void](Invoke-Git add -A)
    $message = "release: Akzo SDD PBI Builder v$version"; if ($Trailer) { $message += "`n`n$Trailer" }
    [void](Invoke-Git commit -m $message)
    [void](Invoke-Git tag -a $tag -m "Akzo SDD PBI Builder $version")
    $head = (Invoke-Git rev-parse HEAD)[0]
}

# ---- 5. Push (fast-forward only) ----
Step "Push $Branch and $tag to $Repository"
[void](Invoke-Git push $remote "HEAD:refs/heads/$Branch")
if (-not $remoteTag) { [void](Invoke-Git push $remote "refs/tags/$tag") }

# ---- 6. GitHub release and assets ----
Step "GitHub release $tag"
$release = Get-Release $tag
if (-not $release) { $release = Invoke-GitHub POST "https://api.github.com/repos/$Repository/releases" @{ tag_name = $tag; name = "Akzo SDD PBI Builder $version"; body = $notes; draft = $false; prerelease = $false } }
$uploadUrl = $release.upload_url -replace '\{.*\}$', ''
foreach ($f in @($zip, $zipSum)) {
    $leaf = Split-Path -Leaf $f; $size = (Get-Item -LiteralPath $f).Length
    $existing = @($release.assets | Where-Object { $_.name -ceq $leaf })
    if ($existing.Count) { if ($existing[0].size -ne $size) { throw "Release asset $leaf already exists with another size; delete it on GitHub, then run again." }; continue }
    $type = if ($leaf.EndsWith('.zip')) { 'application/zip' } else { 'text/plain' }
    [void](Invoke-GitHub POST "$($uploadUrl)?name=$([uri]::EscapeDataString($leaf))" $null ([System.IO.File]::ReadAllBytes($f)) $type)
    Write-Host "Uploaded $leaf ($size bytes)."
}

# ---- 7. Verify the publication ----
Step 'Verify the publication'
$branchLine = @(Invoke-Git ls-remote $remote "refs/heads/$Branch")
if (-not $branchLine.Count -or ($branchLine[0] -split '\s+')[0] -cne $head) { throw "$Repository $Branch does not point at the release commit $head." }
if ((Get-RemoteTagCommit $remote $tag) -cne $head) { throw "Tag $tag on $Repository does not point at the release commit $head." }
$release = Get-Release $tag
if (-not $release -or $release.draft) { throw "Release $tag is missing or still a draft." }
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("pbi-release-" + [guid]::NewGuid().ToString('N').Substring(0, 8)); [void][System.IO.Directory]::CreateDirectory($work)
try {
    foreach ($f in @($zip, $zipSum)) {
        $leaf = Split-Path -Leaf $f; $asset = @($release.assets | Where-Object { $_.name -ceq $leaf })
        if (-not $asset.Count -or $asset[0].state -cne 'uploaded') { throw "Release asset $leaf is missing or not uploaded." }
        # shortcut: anonymous download, which needs a public repository; use the asset API with the token for a private one.
        $copy = Join-Path $work $leaf; Invoke-WebRequest -UseBasicParsing -Uri $asset[0].browser_download_url -OutFile $copy
        if ((Get-Sha256 $copy) -cne (Get-Sha256 $f)) { throw "The downloaded $leaf differs from the local artifact." }
        Write-Host "Verified download: $($asset[0].browser_download_url) (SHA-256 $(Get-Sha256 $copy))"
    }
} finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host ''; Write-Host "Published ${tag}: commit $head on $Repository $Branch, release $($release.html_url)"
