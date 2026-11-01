<#
.SYNOPSIS
Installs, upgrades, verifies, repairs or uninstalls the Akzo SDD PBI Builder in a
repository, checks a PBI's readiness, or refreshes evidence fingerprints.

.DESCRIPTION
Reads pbi-builder-bundle.json, which is generated from the same core.js as the HTML
wizard, so both installers write identical files for the same settings.
Never overwrites user-edited files, existing PBIs, knowledge notes, shared Copilot
instructions or unrelated agents. Updates and retirements are backed up under
playbook/pbi-builder/backups/. Respects the execution policy; never changes it.

Run without -RepoPath for guided mode (folder picker and prompts).

.EXAMPLE
.\Install-PBIBuilder.ps1 -RepoPath "C:\src\My Repo" -ProjectName "My Repo" -Ide vscode -Role dab -Preview
.EXAMPLE
.\Install-PBIBuilder.ps1 -RepoPath "C:\src\My Repo" -AllowUpdates
.EXAMPLE
.\Install-PBIBuilder.ps1 -RepoPath "C:\src\My Repo" -Action CheckPbi -Pbi pbi-300186-formula-20261027-ab12cd34
#>
[CmdletBinding()]
param(
    [ValidateSet('Install', 'Verify', 'Repair', 'Uninstall', 'CheckPbi', 'RefreshEvidence')]
    [string]$Action = 'Install',
    [string]$RepoPath,
    [string]$ProjectName,
    [ValidateSet('visualstudio', 'vscode')][string]$Ide,
    [ValidateSet('legacy', 'dab', 'cdms', 'ui', 'other')][string]$Role,
    [string]$LegacySource,
    [string]$DabSource,
    [string]$CdmsSource,
    [string]$UiSource,
    [string[]]$OtherSource,
    [switch]$NoReferences,
    [switch]$IncludeReferences,
    [switch]$Preview,
    [switch]$AllowUpdates,
    [string]$Pbi,
    [switch]$Json
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Sha = [System.Security.Cryptography.SHA256]::Create()
# Source keys in core.js order (SOURCE_KEYS).
$SourceKeys = @('legacy', 'dab', 'cdms', 'ui')
$Ordinal = [System.StringComparison]::Ordinal
$script:Bound = $PSBoundParameters
$Interactive = -not $PSBoundParameters.ContainsKey('RepoPath')
$script:Repo = $null

# ---- JSON-compatible helpers (values from ConvertFrom-Json; property names case-sensitive, as in JavaScript) ----
function Get-Prop($o, [string]$name) {
    if ($o -is [System.Management.Automation.PSCustomObject]) { $p = $o.PSObject.Properties[$name]; if ($p -and $p.Name -ceq $name) { return , $p.Value } }
    return $null
}
function Test-Has($o, [string]$name) { if (-not ($o -is [System.Management.Automation.PSCustomObject])) { return $false }; $p = $o.PSObject.Properties[$name]; return ($null -ne $p) -and ($p.Name -ceq $name) }
function Set-Prop($o, [string]$name, $value) {
    $p = $o.PSObject.Properties[$name]
    if ($p) { $p.Value = $value } else { Add-Member -InputObject $o -NotePropertyName $name -NotePropertyValue $value }
}
function Test-Obj($x) { return $x -is [System.Management.Automation.PSCustomObject] }
function Test-Str($x) { return ($x -is [string]) -and ($x.Trim() -ne '') }
function Test-Num($x) { return ($x -is [int]) -or ($x -is [long]) -or ($x -is [decimal]) -or ($x -is [double]) }
function Test-Rev($x) { return (Test-Num $x) -and ($x -ge 1) -and ([math]::Floor($x) -eq $x) }
function Test-One($x) { return (Test-Num $x) -and ($x -eq 1) }
function Test-Same($a, $b) { return ($a -is [string]) -and ($b -is [string]) -and [string]::Equals($a, $b, $Ordinal) }
function Test-In($list, $x) { foreach ($i in $list) { if (Test-Same $i $x) { return $true } }; return $false }
function Get-Arr($x) { if ($x -is [array]) { return , $x }; return , @() }
function Test-SameText($a, $b) { if ($null -eq $a -or $null -eq $b) { return ($null -eq $a) -and ($null -eq $b) }; return [string]::Equals($a, $b, $Ordinal) }
function New-Map { return New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal) }

# Same output as JavaScript JSON.stringify(string) without the quotes.
function ConvertTo-JsEscaped([string]$s) {
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $s.Length; $i++) {
        $n = [int]$s[$i]
        if ($n -eq 34) { [void]$sb.Append('\"') }
        elseif ($n -eq 92) { [void]$sb.Append('\\') }
        elseif ($n -eq 8) { [void]$sb.Append('\b') }
        elseif ($n -eq 9) { [void]$sb.Append('\t') }
        elseif ($n -eq 10) { [void]$sb.Append('\n') }
        elseif ($n -eq 12) { [void]$sb.Append('\f') }
        elseif ($n -eq 13) { [void]$sb.Append('\r') }
        elseif ($n -lt 32) { [void]$sb.Append(('\u{0:x4}' -f $n)) }
        elseif ($n -ge 0xD800 -and $n -le 0xDBFF -and $i + 1 -lt $s.Length -and [int]$s[$i + 1] -ge 0xDC00 -and [int]$s[$i + 1] -le 0xDFFF) { [void]$sb.Append($s[$i]).Append($s[$i + 1]); $i++ }
        elseif ($n -ge 0xD800 -and $n -le 0xDFFF) { [void]$sb.Append(('\u{0:x4}' -f $n)) }
        else { [void]$sb.Append($s[$i]) }
    }
    return $sb.ToString()
}

# ---- Files relative to the repository root ----
function Test-SafePath($path) {
    if (-not ($path -is [string]) -or $path -eq '' -or $path.Contains('\') -or $path.StartsWith('/')) { return $false }
    # Windows device names and trailing dots/spaces silently alias other files, so they are rejected too.
    foreach ($s in $path.Split('/')) { if ($s -eq '' -or $s -eq '.' -or $s -eq '..' -or $s -match '[\x00-\x1f<>:"|?*]' -or $s -match '[. ]$' -or $s -match '^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$') { return $false } }
    return $true
}
function Get-Full([string]$rel) {
    if (-not (Test-SafePath $rel)) { throw "Invalid relative file path: $rel" }
    $full = $script:Repo
    foreach ($part in $rel.Split('/')) {
        $full = [System.IO.Path]::Combine($full, $part)
        try { $attributes = [System.IO.File]::GetAttributes($full) }
        catch [System.IO.FileNotFoundException] { continue }
        catch [System.IO.DirectoryNotFoundException] { continue }
        if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Repository path contains a junction or reparse point; refusing access: $rel"
        }
    }
    return $full
}
function Read-Text([string]$rel) { $f = Get-Full $rel; if ([System.IO.File]::Exists($f)) { return [System.IO.File]::ReadAllText($f, $Utf8) }; return $null }
function Write-Text([string]$rel, [string]$text) {
    $f = Get-Full $rel
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($f))
    [System.IO.File]::WriteAllText($f, $text, $Utf8)
}
function Remove-File([string]$rel) { $f = Get-Full $rel; if ([System.IO.File]::Exists($f)) { [System.IO.File]::Delete($f) } }
function Get-Hash([byte[]]$bytes) { return (($Sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '') }
function Get-TextHash([string]$t) { return Get-Hash $Utf8.GetBytes($t) }
function Get-Batch { return [DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8) }

# ---- Generation contract ----
function Read-Bundle {
    $path = Join-Path $PSScriptRoot 'pbi-builder-bundle.json'
    if (-not [System.IO.File]::Exists($path)) { throw 'pbi-builder-bundle.json is missing next to this script. Use the complete package.' }
    try { $b = [System.IO.File]::ReadAllText($path, $Utf8) | ConvertFrom-Json } catch { throw "pbi-builder-bundle.json is not valid JSON: $($_.Exception.Message)" }
    if (-not (Test-One (Get-Prop $b 'schemaVersion'))) { throw "Unsupported bundle schemaVersion '$(Get-Prop $b 'schemaVersion')'. This installer reads version 1; use the installer from the same package." }
    return $b
}
function Read-Line($value, [int]$max, [string]$what) {
    $s = ([string]$value).Trim()
    if ($s -eq '' -or $s -match '[\x00-\x1f]' -or $s.Length -gt $max) { throw "Enter a single-line $what (1-$max characters)." }
    return $s
}
# Mirrors normalizeConfig() in core.js.
function New-Config($in) {
    if ($null -ne $in.schemaVersion -and -not (Test-One $in.schemaVersion)) { throw "Unsupported config schemaVersion $($in.schemaVersion); this package reads version 1." }
    $name = Read-Line $in.projectName 100 'project name'
    $ideValue = if ([string]$in.ide -ceq 'vscode') { 'vscode' } else { 'visualstudio' }
    if (-not (Test-In @('legacy', 'dab', 'cdms', 'ui', 'other') ([string]$in.role))) { throw 'Choose the role of this repository: legacy, dab, cdms, ui or other.' }
    $sources = [ordered]@{}
    foreach ($k in $SourceKeys) {
        $v = ([string]$in.sources[$k]).Trim()
        if ($v -match '[\x00-\x1f]') { throw 'Source paths must be on one line.' }
        $sources[$k] = $v.Replace('\', '/')
    }
    if ($in.role -cne 'other') { $sources[[string]$in.role] = '.' }
    $raw = @($in.others | Where-Object { $null -ne $_ })
    if ($raw.Count -gt 10) { throw 'Configure at most 10 other repositories.' }
    $others = @()
    foreach ($o in $raw) {
        $n = Read-Line $o.name 60 'name'
        $p = ([string]$o.path).Trim().Replace('\', '/')
        if ($p -eq '' -or $p -match '[\x00-\x1f]') { throw "Give each other repository one path on one line: $n" }
        if ((Test-In $SourceKeys $n.ToLowerInvariant()) -or @($others | Where-Object { $_.name.ToLowerInvariant() -ceq $n.ToLowerInvariant() }).Count) { throw "Other repository names must be unique and not Legacy, DAB, CDMS or UI: $n" }
        $others += [pscustomobject]@{ name = $n; path = $p }
    }
    return [ordered]@{ schemaVersion = 1; packageVersion = [string]$Bundle.packageVersion; projectName = $name; ide = $ideValue; role = [string]$in.role
        agentName = [string]$Bundle.agentPrefix + $name; includeReferences = [bool]$in.includeReferences; sources = $sources; others = $others }
}
function ConvertTo-ConfigJson($c) {
    $q = { param($v) '"' + (ConvertTo-JsEscaped $v) + '"' }
    # Same layout as JSON.stringify(config, null, 2).
    $others = if ($c.others.Count) { "[`n" + (@($c.others | ForEach-Object { "    {`n      `"name`": $(& $q $_.name),`n      `"path`": $(& $q $_.path)`n    }" }) -join ",`n") + "`n  ]" } else { '[]' }
    return (@('{', '  "schemaVersion": 1,', "  `"packageVersion`": $(& $q $c.packageVersion),", "  `"projectName`": $(& $q $c.projectName),",
            "  `"ide`": $(& $q $c.ide),", "  `"role`": $(& $q $c.role),", "  `"agentName`": $(& $q $c.agentName),",
            "  `"includeReferences`": $(if ($c.includeReferences) { 'true' } else { 'false' }),", '  "sources": {',
            "    `"legacy`": $(& $q $c.sources.legacy),", "    `"dab`": $(& $q $c.sources.dab),", "    `"cdms`": $(& $q $c.sources.cdms),", "    `"ui`": $(& $q $c.sources.ui)", '  },', "  `"others`": $others", '}') -join "`n")
}
function Get-Values($c) {
    $v = New-Map
    $v['PROJECT'] = $c.projectName; $v['PROJECT_ESC'] = ConvertTo-JsEscaped $c.projectName; $v['ROLE'] = $c.role
    $v['SRC_LEGACY_ESC'] = ConvertTo-JsEscaped $c.sources.legacy; $v['SRC_DAB_ESC'] = ConvertTo-JsEscaped $c.sources.dab; $v['SRC_CDMS_ESC'] = ConvertTo-JsEscaped $c.sources.cdms; $v['SRC_UI_ESC'] = ConvertTo-JsEscaped $c.sources.ui
    $v['ANALYSIS_DOCS'] = if ($c.includeReferences) { [string]$Bundle.analysisDocs.included } else { [string]$Bundle.analysisDocs.excluded }
    $v['OTHER_SOURCES'] = if ($c.others.Count) { -join @($c.others | ForEach-Object { "`n  - name: `"$(ConvertTo-JsEscaped $_.name)`"`n    repositoryPath: `"$(ConvertTo-JsEscaped $_.path)`"" }) } else { [string]$Bundle.analysisDocs.excluded }
    $v['CONFIG_JSON'] = ConvertTo-ConfigJson $c
    $ideProfile = Get-Prop $Bundle.ideProfiles $c.ide
    foreach ($p in $ideProfile.PSObject.Properties) { $v[$p.Name] = [string]$p.Value }
    foreach ($t in $Bundle.tokens) { if (-not $v.ContainsKey($t)) { throw "The bundle declares placeholder $t that this installer cannot fill. Use the installer from the same package." } }
    return $v
}
function Invoke-Render([string]$template, $values, [string]$label) {
    $out = New-Object System.Text.StringBuilder; $last = 0
    foreach ($m in [regex]::Matches($template, '\{\{PBI:([A-Z0-9_]+)\}\}')) {
        $k = $m.Groups[1].Value
        if (-not $values.ContainsKey($k)) { throw "Unresolved placeholder {{PBI:$k}} in $label" }
        [void]$out.Append($template, $last, $m.Index - $last).Append($values[$k]); $last = $m.Index + $m.Length
    }
    return $out.Append($template, $last, $template.Length - $last).ToString()
}
function Get-SetupFiles($c, [string]$html) {
    $values = Get-Values $c
    $files = New-Object System.Collections.Specialized.OrderedDictionary ([System.StringComparer]::Ordinal)
    foreach ($t in $Bundle.setup) {
        $when = Get-Prop $t 'when'
        if ($when -and -not $c[[string]$when]) { continue }
        if ((Get-Prop $t 'source') -ceq 'html') { $files[$t.path] = $html }
        elseif (Test-Has $t 'text') { $files[$t.path] = [string]$t.text }
        else { $files[$t.path] = Invoke-Render ([string]$t.template) $values $t.path }
    }
    return $files
}
function Get-BaselineText($c, $baseline) { return Invoke-Render ([string]$baseline.template) (Get-Values $c) $baseline.path }

# ---- Plan and apply: same states and order as plan()/apply() in core.js ----
function Read-Manifest {
    $raw = Read-Text $Bundle.manifest
    if ($null -eq $raw) { return $null }
    try { $m = $raw | ConvertFrom-Json } catch { throw 'The existing installation record is invalid. Preserve it and compare manually.' }
    if (-not (Test-One (Get-Prop $m 'schemaVersion')) -or -not (Test-Obj (Get-Prop $m 'files'))) { throw 'Unrecognized installation record.' }
    return $m
}
function ConvertTo-ManifestJson($rows) {
    $entries = @($rows | Where-Object { $null -ne $_.text } | ForEach-Object { '    "' + (ConvertTo-JsEscaped $_.path) + '": "' + (Get-TextHash $_.text) + '"' })
    $files = if ($entries.Count) { "{`n" + ($entries -join ",`n") + "`n  }" } else { '{}' }
    return "{`n  `"schemaVersion`": 1,`n  `"packageVersion`": `"$(ConvertTo-JsEscaped $Bundle.packageVersion)`",`n  `"files`": $files`n}`n"
}
function Get-Plan($files) {
    $old = Read-Manifest
    $owned = New-Map
    if ($old) { foreach ($p in $old.files.PSObject.Properties) { $owned[$p.Name] = $p.Value } }
    $rows = New-Object System.Collections.ArrayList
    foreach ($path in $files.Keys) {
        $text = $files[$path]; $before = Read-Text $path
        $state = if ($null -eq $before) { 'create' } elseif (Test-SameText $before $text) { 'unchanged' } else { 'conflict' }
        if ($state -ceq 'conflict' -and $owned.ContainsKey($path) -and (Test-Same $owned[$path] (Get-TextHash $before))) { $state = 'update' }
        [void]$rows.Add([pscustomobject]@{ path = $path; text = $text; before = $before; state = $state })
    }
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($p in @($owned.Keys) + @($Bundle.legacyFiles)) { if (-not $candidates.Contains($p)) { $candidates.Add($p) } }
    foreach ($path in $candidates) {
        if ($files.Contains($path) -or $path -ceq $Bundle.manifest) { continue }
        $before = Read-Text $path
        if ($null -eq $before) { continue }
        $state = if ($owned.ContainsKey($path) -and (Test-Same $owned[$path] (Get-TextHash $before))) { 'retire' } else { 'retire-conflict' }
        [void]$rows.Add([pscustomobject]@{ path = $path; text = $null; before = $before; state = $state })
    }
    $text = ConvertTo-ManifestJson $rows; $before = Read-Text $Bundle.manifest
    $state = if ($null -eq $before) { 'create' } elseif (Test-SameText $before $text) { 'unchanged' } else { 'update' }
    [void]$rows.Add([pscustomobject]@{ path = $Bundle.manifest; text = $text; before = $before; state = $state })
    return , $rows
}
function Invoke-Apply($rows, [bool]$allow) {
    $blocked = @($rows | Where-Object { $_.state -ceq 'conflict' })
    if ($blocked.Count) { throw ("Existing files differ. Nothing was written. Resolve these files first:`n" + (($blocked | ForEach-Object { $_.path }) -join "`n")) }
    if (@($rows | Where-Object { $_.state -ceq 'update' -or $_.state -ceq 'retire' }).Count -and -not $allow) { throw 'Review and allow updates to the previously installed files (-AllowUpdates) before continuing.' }
    foreach ($r in $rows) { if (-not (Test-SameText (Read-Text $r.path) $r.before)) { throw "A file changed after review. Nothing was written. Review setup again: $($r.path)" } }
    $batch = Get-Batch; $touched = New-Object System.Collections.ArrayList; $backups = New-Object System.Collections.ArrayList
    $complete = $false; $message = 'Interrupted (for example Ctrl+C).'
    try {
        foreach ($r in @($rows | Where-Object { $_.state -ceq 'update' -or $_.state -ceq 'retire' })) {
            $b = "$($Bundle.base)/backups/$batch/$($r.path)"
            if ($null -ne (Read-Text $b)) { throw "Backup collision: $b" }
            Write-Text $b $r.before; [void]$backups.Add($b)
        }
        foreach ($r in @($rows | Where-Object { $_.state -ceq 'create' -or $_.state -ceq 'update' })) {
            [void]$touched.Add($r); Write-Text $r.path $r.text
            if (-not (Test-SameText (Read-Text $r.path) $r.text)) { throw "Saved content did not match: $($r.path)" }
        }
        # Retire only after every new file is written and verified.
        foreach ($r in @($rows | Where-Object { $_.state -ceq 'retire' })) { [void]$touched.Add($r); Remove-File $r.path }
        $complete = $true
    }
    catch { $message = $_.Exception.Message }
    # finally also runs on Ctrl+C, where catch does not. A killed process skips both; rerunning Install completes it.
    finally {
        if (-not $complete) {
            $errors = @()
            for ($i = $touched.Count - 1; $i -ge 0; $i--) {
                $r = $touched[$i]
                try { if ($null -eq $r.before) { Remove-File $r.path } else { Write-Text $r.path $r.before } } catch { $errors += "$($r.path): $($_.Exception.Message)" }
            }
            $tail = if ($errors.Count) { "Some files could not be restored:`n" + ($errors -join "`n") } else { 'Previously touched files were restored; any backups and empty folders were retained.' }
        }
    }
    if (-not $complete) { throw "File write failed: $message`n$tail" }
    return [pscustomobject]@{ written = @($rows | Where-Object { $_.state -ceq 'create' -or $_.state -ceq 'update' }).Count; backups = $backups
        retired = @($rows | Where-Object { $_.state -ceq 'retire' } | ForEach-Object { $_.path }); kept = @($rows | Where-Object { $_.state -ceq 'retire-conflict' } | ForEach-Object { $_.path }) }
}
function Show-Plan($rows) {
    foreach ($r in $rows) { Write-Host ('{0,-16} {1}' -f $r.state, $r.path) }
    $counts = $rows | Group-Object state | ForEach-Object { "$($_.Count) $($_.Name)" }
    Write-Host ("Review: " + ($counts -join ', '))
    if (@($rows | Where-Object { $_.state -ceq 'retire' }).Count) { Write-Host 'retire: unchanged earlier-version files are backed up, then removed after the new files are verified.' }
    if (@($rows | Where-Object { $_.state -ceq 'retire-conflict' }).Count) { Write-Host 'retire-conflict: edited or unowned earlier-version files are kept. Delete them yourself, or change their name: line to keep a personal copy.' }
    if (@($rows | Where-Object { $_.state -ceq 'conflict' }).Count) { Write-Host 'conflict: these files differ from the installed record and are never overwritten. Restore or move them, then rerun.' -ForegroundColor Yellow }
}

# ---- Readiness: mirrors readiness() in core.js; test-ps.cjs proves equivalence ----
function Get-Norm([string]$s) { return [regex]::Replace($s, '[ \t\r\n]+', ' ').Trim(' ') }
function Get-Keys($o) { $k = [string[]]@($o.PSObject.Properties | ForEach-Object { $_.Name }); [array]::Sort($k, [System.StringComparer]::Ordinal); return , $k }
# Canonical JSON identical to canon() in core.js: sorted keys, whitespace runs in text collapsed.
function ConvertTo-Canon($x, [bool]$binaryNumbers = $false) {
    if ($null -eq $x) { return 'null' }
    if ($x -is [string]) { return '"' + (ConvertTo-JsEscaped (Get-Norm $x)) + '"' }
    if ($x -is [bool]) { if ($x) { return 'true' }; return 'false' }
    if (Test-Num $x) {
        $d = [double]$x
        if ($binaryNumbers) {
            if ($d -eq 0) { $d = 0.0 }
            $bytes = [BitConverter]::GetBytes($d)
            if ([BitConverter]::IsLittleEndian) { [array]::Reverse($bytes) }
            return '#' + [BitConverter]::ToString($bytes).Replace('-', '').ToLowerInvariant()
        }
        # Existing approval fingerprints retain their historical numeric formatting.
        if ([math]::Floor($d) -eq $d -and [math]::Abs($d) -lt 1e15) { return ([long]$d).ToString([Globalization.CultureInfo]::InvariantCulture) }
        return $d.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
    }
    if ($x -is [array]) { $p = New-Object System.Collections.Generic.List[string]; foreach ($i in $x) { $p.Add((ConvertTo-Canon $i $binaryNumbers)) }; return '[' + ($p -join ',') + ']' }
    if ($x -is [System.Collections.IDictionary]) { $k = [string[]]@($x.Keys); [array]::Sort($k, [System.StringComparer]::Ordinal); return '{' + ((@($k | ForEach-Object { '"' + (ConvertTo-JsEscaped $_) + '":' + (ConvertTo-Canon $x[$_] $binaryNumbers) })) -join ',') + '}' }
    if (Test-Obj $x) { return '{' + ((@((Get-Keys $x) | ForEach-Object { '"' + (ConvertTo-JsEscaped $_) + '":' + (ConvertTo-Canon $x.PSObject.Properties[$_].Value $binaryNumbers) })) -join ',') + '}' }
    return 'null'
}
function Get-Fp($x) { return (Get-TextHash (ConvertTo-Canon $x)).Substring(0, 16) }
function Get-ReviewFingerprint([string]$folder, $sourceFiles = $null) {
    $inputs = New-Map
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = [int]::MaxValue
    foreach ($name in @('pbi.json', 'REQUEST.md', 'DRAFT-PBI.md', 'EVIDENCE.md', 'OPEN-QUESTIONS.md', 'DECISION-LOG.md', 'VALIDATION-MATRIX.md')) {
        $full = Get-Full "$folder/$name"
        if ([System.IO.File]::Exists($full)) {
            $bytes = [System.IO.File]::ReadAllBytes($full)
            $text = $null
            try { $text = $strictUtf8.GetString($bytes) } catch [System.Text.DecoderFallbackException] { }
            if ($null -ne $text) {
                if ($text.StartsWith([string][char]0xFEFF, [System.StringComparison]::Ordinal)) { $text = $text.Substring(1) }
                if ($name -ceq 'pbi.json') {
                    try { $parsed = $serializer.DeserializeObject($text); $text = ConvertTo-Canon $parsed $true }
                    catch {
                        if (-not ($_.Exception.InnerException -is [System.ArgumentException]) -and -not ($_.Exception.InnerException -is [System.InvalidOperationException])) { throw }
                    }
                }
                else {
                    $text = $text.Replace("`r`n", "`n")
                    if ($name -ceq 'DRAFT-PBI.md') { $text = [regex]::Replace($text, '(?m)^Status:.*$', 'Status: <generated-status>') }
                }
                $bytes = $Utf8.GetBytes($text)
            }
            $inputs[$name] = Get-Hash $bytes
        }
    }
    $statePath = "$folder/pbi-state.json"
    $stateRaw = Read-Text $statePath
    $sources = New-Object System.Collections.Generic.List[string]
    if ($null -ne $stateRaw) {
        try {
            $state = $serializer.DeserializeObject($stateRaw)
            if ($state -is [System.Collections.IDictionary]) {
                if ($state['evidence'] -is [array]) {
                    foreach ($e in $state['evidence']) {
                        if ($e -is [System.Collections.IDictionary] -and (Test-Same $e['kind'] 'repo-file') -and (Test-SafePath $e['source']) -and -not $sources.Contains([string]$e['source'])) { $sources.Add([string]$e['source']) }
                    }
                }
                [void]$state.Remove('status'); [void]$state.Remove('approvalHistory')
                $approvals = $state['approvals']
                if ($approvals -is [System.Collections.IDictionary]) { [void]$approvals.Remove('user') }
            }
            $inputs['pbi-state.json'] = Get-TextHash (ConvertTo-Canon $state)
        }
        catch {
            if (-not ($_.Exception.InnerException -is [System.ArgumentException]) -and -not ($_.Exception.InnerException -is [System.InvalidOperationException])) { throw }
            $inputs['pbi-state.json'] = Get-Hash ([System.IO.File]::ReadAllBytes((Get-Full $statePath)))
        }
    }
    if ($sources.Count) {
        $paths = [string[]]$sources.ToArray(); [array]::Sort($paths, [System.StringComparer]::Ordinal)
        $sourceRows = New-Object System.Collections.Generic.List[object]
        foreach ($source in $paths) {
            if ($null -ne $sourceFiles -and $sourceFiles.ContainsKey($source)) { $h = $sourceFiles[$source] }
            else { $full = Get-Full $source; $h = if ([System.IO.File]::Exists($full)) { Get-Hash ([System.IO.File]::ReadAllBytes($full)) } else { $null } }
            $sourceRows.Add(@($source, $h))
        }
        $inputs['evidenceSources'] = $sourceRows.ToArray()
    }
    $attachmentsPath = Get-Full "$folder/attachments"
    if ([System.IO.Directory]::Exists($attachmentsPath)) {
        $names = [string[]]@([System.IO.Directory]::GetFiles($attachmentsPath) | ForEach-Object { [System.IO.Path]::GetFileName($_) })
        [array]::Sort($names, [System.StringComparer]::Ordinal)
        $rows = New-Object System.Collections.Generic.List[object]
        foreach ($name in $names) {
            $bytes = [System.IO.File]::ReadAllBytes((Get-Full "$folder/attachments/$name"))
            $rows.Add(@($name, (Get-Hash $bytes)))
        }
        $inputs['attachments'] = $rows.ToArray()
    }
    return Get-TextHash (ConvertTo-Canon $inputs)
}
function Test-Meaningful($t) { return ($t -is [string]) -and (Get-Norm $t).Length -ge 12 -and -not [regex]::IsMatch($t, '(^|[^A-Za-z0-9])(TBD|TODO|TBC)([^A-Za-z0-9]|$)', 'IgnoreCase, CultureInvariant') }
function Get-DocNorm([string]$s) { return Get-Norm ([regex]::Replace($s, '[*`]', '')) }
function Test-HasId([string]$doc, [string]$id) { return [regex]::IsMatch($doc, '(^|[^A-Za-z0-9_-])' + [regex]::Escape($id) + '([^A-Za-z0-9_-]|$)') }
function Get-Shown($l) { if ($l -is [string]) { return $l } elseif ($null -eq $l) { return 'null' } elseif ($l -is [bool]) { if ($l) { return 'true' }; return 'false' } elseif (Test-Num $l) { return [string]$l }; return ConvertTo-Json -InputObject $l -Compress -Depth 20 }
function Find-Id($list, $id) { foreach ($x in $list) { if ((Test-Obj $x) -and (Test-Str (Get-Prop $x 'id')) -and (Test-Same $x.id $id)) { return $x } }; return $null }
function Test-BranchProven([string]$app, $evidence, [bool]$scripted, $registration) {
    if ($app -ceq 'cdms' -and $scripted -and -not (Test-Same $registration 'active')) { return $false }
    foreach ($e in $evidence) {
        $system = Get-Prop $e 'system'; $component = Get-Prop $e 'component'
        if ($app -ceq 'ui') { if ((Test-Same $system 'ui') -or (-not (Test-Has $e 'system') -and (Test-In @('javascript', 'web-resource', 'ribbon') $component))) { return $true } }
        elseif ($app -ceq 'cdms') { if (-not (Test-In @('dab', 'ui', 'ocp', 'graphql') $system) -and -not (Test-Same $component 'dab') -and -not ((-not (Test-Has $e 'system')) -and (Test-In @('javascript', 'web-resource', 'ribbon') $component))) { return $true } }
        elseif (-not (Test-In @('legacy-crm', 'cdms', 'ui', 'ocp', 'graphql') $system) -and ((Test-Same $system 'dab') -or -not (Test-In @('cdms-api', 'plugin', 'workflow', 'custom-activity', 'xrm-service', 'javascript', 'web-resource', 'ribbon') $component))) { return $true }
    }
    return $false
}
# Final document keys in core.js order (cdmsRefined, dabRefined, uiRefined).
function Get-FinalKeys { return @($Bundle.readiness.finalDocs.PSObject.Properties | ForEach-Object { $_.Name }) }
function Get-Readiness($state, $docs, [string]$pbi) {
    $Spec = $Bundle.readiness; $S = @($Spec.statuses)
    $issues = New-Object System.Collections.ArrayList
    $add = { param($code, [int]$cap, $ref) [void]$issues.Add([ordered]@{ code = $code; cap = $S[$cap]; ref = [string]$ref; message = [string](Get-Prop $Spec.messages $code) }) }
    $files = $docs.files
    $fileOf = { param($p) if (($p -is [string]) -and $files.ContainsKey($p)) { $files[$p] } else { $null } }
    $sv = Get-Prop $state 'schemaVersion'
    $valid = (Test-Obj $state) -and (Test-Num $sv) -and ($sv -eq 1 -or $sv -eq 2)
    $review = [ordered]@{}
    if (-not (Test-Obj $state)) { & $add 'STATE_MISSING' 0 $pbi }
    elseif (-not $valid) { & $add 'STATE_SCHEMA' 0 $pbi }
    else {
        if ($sv -eq 1) { & $add 'STATE_OUTDATED' 0 $pbi }
        if (-not (Test-Same (Get-Prop $state 'pbi') $pbi)) { & $add 'STATE_PBI_MISMATCH' 0 $pbi }
        if (-not (Test-In $S (Get-Prop $state 'status'))) { & $add 'STATUS_INVALID' 0 $pbi }
        if ($null -eq $docs.request) { & $add 'REQUEST_MISSING' 0 $pbi }
        $Lists = @{}; foreach ($n in $Spec.lists) { $Lists[$n] = Get-Arr (Get-Prop $state $n) }
        $rules = $Lists['rules']; $acs = $Lists['acceptanceCriteria']; $actors = $Lists['actors']; $evidence = $Lists['evidence']; $decisions = $Lists['decisions']; $deps = $Lists['dependencies']
        if (-not $rules.Count) { & $add 'NO_RULES' 0 $pbi }
        if (-not $acs.Count) { & $add 'NO_ACS' 0 $pbi }
        if (-not $actors.Count) { & $add 'NO_ACTORS' 0 $pbi }
        if (-not ((Get-Prop $state 'dependencies') -is [array])) { & $add 'NO_DEPENDENCIES' 0 $pbi }
        $seen = New-Object System.Collections.Generic.List[string]
        foreach ($n in $Spec.lists) { foreach ($x in $Lists[$n]) { $id = Get-Prop $x 'id'; if (-not (Test-Str $id)) { continue }; if ($seen.Contains($id)) { & $add 'DUPLICATE_ID' 0 $id } else { $seen.Add($id) } } }
        # Files from another PBI's folder are never evidence for this one.
        $isForeign = { param($x) $src = Get-Prop $x 'source'; return ($src -is [string]) -and $src.StartsWith('playbook/pbis/', [System.StringComparison]::Ordinal) -and -not $src.StartsWith("playbook/pbis/$pbi/", [System.StringComparison]::Ordinal) }
        foreach ($x in $evidence) { if ((Test-Obj $x) -and (& $isForeign $x)) { $id = Get-Prop $x 'id'; & $add 'FOREIGN_PBI_EVIDENCE' 1 $(if (Test-Str $id) { $id } else { $pbi }) } }
        $isHist = { param($x) if ((Get-Prop $x 'historical') -eq $true -and (Get-Prop $x 'historical') -is [bool]) { return $true }; if (& $isForeign $x) { return $true }; $src = Get-Prop $x 'source'; if (-not (Test-Same (Get-Prop $x 'kind') 'repo-file') -or -not ($src -is [string])) { return $false }; foreach ($p in $Spec.historicalPaths) { if ($p.EndsWith('/')) { if ($src.StartsWith($p, [System.StringComparison]::Ordinal)) { return $true } } elseif (Test-Same $src $p) { return $true } }; return $false }
        $evScope = Get-Prop $state 'evidenceScope'; $excluded = @((Get-Arr (Get-Prop $evScope 'exclude')) | Where-Object { $_ -is [string] })
        if ($excluded.Count -and -not (Test-Same (Get-Prop (Find-Id $decisions (Get-Prop $evScope 'decisionRef')) 'status') 'approved')) { & $add 'SCOPE_DECISION_MISSING' 2 $pbi }
        $scope = Get-Prop $state 'paths'; if (-not (Test-Obj $scope)) { $scope = [pscustomobject]@{} }
        $applies = New-Object System.Collections.Generic.List[string]
        $target = if (($docs.application -is [string]) -and (Test-Has $Spec.targetPaths $docs.application)) { @(Get-Prop $Spec.targetPaths $docs.application) } else { $null }
        foreach ($k in $(if ($null -ne $target) { $target } else { $Spec.requiredPaths })) { if (-not (Test-Has $scope $k)) { & $add 'PATH_SCOPE_MISSING' 1 $k } }
        foreach ($k in (Get-Keys $scope)) {
            $v = Get-Prop $scope $k; $ap = Get-Prop $v 'applies'
            if (-not (Test-Obj $v) -or -not ($ap -is [bool]) -or (-not $ap -and -not (Test-Str (Get-Prop $v 'reason')))) { & $add 'PATH_SCOPE_MISSING' 1 $k } elseif ($ap) { $applies.Add($k) }
        }
        if ($null -ne $target) { foreach ($k in $Spec.targetKeys) { if (($target -notcontains $k) -and $applies.Contains($k)) { & $add 'TARGET_SCOPE_CONFLICT' 2 $k } } }
        $ruleIds = @($rules | Where-Object { (Test-Obj $_) -and (Test-Str (Get-Prop $_ 'id')) } | ForEach-Object { $_.id })
        $ruleTexts = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt $rules.Count; $i++) {
            $r = $rules[$i]; $rid = Get-Prop $r 'id'; $id = if ((Test-Obj $r) -and (Test-Str $rid)) { $rid } else { "rule $($i + 1)" }
            $owner = Get-Prop $r 'owner'; $cov = Get-Prop $r 'coverage'; $action = Get-Prop $r 'targetAction'
            $badCov = (Test-Has $r 'coverage') -and (-not ($cov -is [array]) -or @($cov | Where-Object { -not (Test-In $Spec.acTypes $_) }).Count)
            if (-not (Test-Obj $r) -or -not (Test-Str $rid) -or -not (Test-Rev (Get-Prop $r 'rev')) -or -not (Test-Str (Get-Prop $r 'context')) -or -not (Test-Obj $owner) -or -not (Test-In $Spec.owners (Get-Prop $owner 'type')) -or -not (Test-In $Spec.actions $action) -or $badCov) { & $add 'RULE_INCOMPLETE' 0 $id; continue }
            $otype = Get-Prop $owner 'type'; $otypes = Get-Prop $owner 'types'
            if ((Test-Same $otype 'multiple') -and (-not ($otypes -is [array]) -or $otypes.Count -lt 2 -or @($otypes | Where-Object { -not (Test-In $Spec.ownerParts $_) }).Count)) { & $add 'RULE_INCOMPLETE' 0 $id; continue }
            if (-not (Test-Meaningful (Get-Prop $r 'rule'))) { & $add 'CONTENT_MISSING' 0 $id }
            $reg = Get-Prop $r 'registration'
            $types = if (Test-Same $otype 'multiple') { $otypes } else { @($otype) }
            $scripted = @($types | Where-Object { Test-In $Spec.scripted $_ }).Count -gt 0
            if ($scripted -and (-not (Test-In $Spec.registration $reg) -or (Test-Same $reg 'unknown'))) { & $add 'REGISTRATION_UNKNOWN' 1 $id }
            $levels = New-Object System.Collections.ArrayList; $comps = New-Object System.Collections.ArrayList
            $hist = $false
            foreach ($e in (Get-Arr (Get-Prop $r 'evidence'))) {
                $x = Find-Id $evidence $e
                if ($null -eq $x) { & $add 'EVIDENCE_UNKNOWN' 1 "$id/$(Get-Shown $e)" } elseif (Test-In $excluded (Get-Prop $x 'system')) { & $add 'EVIDENCE_OUT_OF_SCOPE' 1 "$id/$(Get-Shown $e)" }
                elseif (& $isHist $x) { $hist = $true }
                else { [void]$levels.Add((Get-Prop $x 'level')); if ((Test-Same (Get-Prop $x 'level') 'code') -and (Test-Has $x 'component')) { [void]$comps.Add((Get-Prop $x 'component')) } }
            }
            if (Test-Same $otype 'unknown') { & $add 'OWNER_UNKNOWN' 1 $id } elseif (-not (Test-Same $otype 'none') -and -not (Test-In $levels 'code')) { & $add 'NO_EVIDENCE' 1 $id }
            if ($hist -and -not (Test-In $levels 'code')) { & $add 'HISTORICAL_NOT_PROOF' 1 $id }
            # Only judged when the code evidence names its component, so older states are unaffected.
            if ($comps.Count) { foreach ($t in $types) { if ((Test-In $Spec.attributed $t) -and -not (Test-In $comps $t)) { & $add 'OWNER_MISATTRIBUTED' 1 "$id/$t" } } }
            if ($scripted -and ((Test-Same $reg 'active') -or (Test-Same $reg 'disabled') -or (Test-Same $reg 'missing')) -and -not (Test-In $levels 'registration')) { & $add 'LEVEL_EVIDENCE_MISSING' 1 "$id/registration" }
            if ((Test-Same (Get-Prop $r 'runtime') 'verified') -and -not (Test-In $levels 'runtime')) { & $add 'LEVEL_EVIDENCE_MISSING' 1 "$id/runtime" }
            $paths = Get-Prop $r 'paths'; if (-not (Test-Obj $paths)) { $paths = [pscustomobject]@{} }
            foreach ($k in $applies) { if (-not (Test-Has $paths $k)) { & $add 'PATH_UNKNOWN' 1 "$id/$k" } }
            foreach ($k in (Get-Keys $paths)) {
                $p = Get-Prop $paths $k; $st = Get-Prop $p 'status'
                if (-not $applies.Contains($k)) { if ((Test-Same $st 'reaches') -or (Test-Same $st 'bypasses')) { & $add 'PATH_CONFLICT' 1 "$id/$k" }; continue }
                if (-not (Test-In $Spec.pathStatus $st) -or (Test-Same $st 'unknown') -or ((Test-Same $st 'not-applicable') -and -not (Test-Str (Get-Prop $p 'reason')))) { & $add 'PATH_UNKNOWN' 1 "$id/$k"; continue }
                if (Test-Same $st 'not-applicable') { continue }
                $reach = $false
                foreach ($e in (Get-Arr (Get-Prop $p 'evidence'))) {
                    $x = Find-Id $evidence $e
                    if ($null -eq $x) { & $add 'EVIDENCE_UNKNOWN' 1 "$id/$k/$(Get-Shown $e)" }
                    elseif (Test-In $excluded (Get-Prop $x 'system')) { & $add 'EVIDENCE_OUT_OF_SCOPE' 1 "$id/$k/$(Get-Shown $e)" }
                    elseif ((Test-Same (Get-Prop $x 'system') 'legacy-crm') -and -not (Test-Same $k 'cdms')) { & $add 'LEGACY_NOT_TARGET_EVIDENCE' 1 "$id/$k/$(Get-Shown $e)" }
                    elseif ((Test-Same (Get-Prop $x 'level') 'reach') -and -not (& $isHist $x)) { $reach = $true }
                }
                if (-not $reach) { & $add 'LEVEL_EVIDENCE_MISSING' 1 "$id/$k" }
            }
            if ((Test-Same $action 'resolve-gap') -or @((Get-Arr (Get-Prop $r 'gaps')) | Where-Object { -not (Test-Obj $_) -or -not (Test-Same (Get-Prop $_ 'status') 'resolved') }).Count) { & $add 'EVIDENCE_GAP' 1 $id }
            $bypass = $false; foreach ($k in $applies) { $p = Get-Prop $paths $k; if ((-not (Test-Same $k 'dab') -or -not (Test-Has $r 'dab')) -and (Test-Has $paths $k) -and (Test-Obj $p) -and (Test-Same (Get-Prop $p 'status') 'bypasses')) { $bypass = $true } }
            if ((Test-Same $action 'reuse') -and (($scripted -and ((Test-Same $reg 'disabled') -or (Test-Same $reg 'missing'))) -or $bypass)) { & $add 'REUSE_NOT_ENFORCED' 1 $id }
            if (Test-Has $r 'dab') {
                $b = Get-Prop $r 'dab'; $layer = Get-Prop $b 'layer'; $bst = Get-Prop $b 'status'
                if ((Test-Obj $b) -and ($layer -is [string]) -and $layer -match '(?i)plugin') { & $add 'DAB_PLUGIN_ASSIGNED' 1 $id }
                elseif (-not (Test-Obj $b) -or -not (Test-In $Spec.dabStatus $bst) -or $(if (Test-Same $bst 'not-applicable') { -not (Test-Str (Get-Prop $b 'reason')) } else { -not (Test-In $Spec.dabLayers $layer) })) { & $add 'DAB_OWNER_INVALID' 1 $id }
            }
            if (Test-Has $r 'branches') {
                # Every material branch is tracked separately: one covered branch never covers the rule.
                $apps = @($Spec.branchApps | Where-Object { $applies.Contains($_) })
                $bad = New-Object System.Collections.Generic.List[string]; $open = New-Object System.Collections.Generic.List[string]; $bids = New-Object System.Collections.Generic.List[string]
                $brs = Get-Prop $r 'branches'
                if (-not ($brs -is [array]) -or $brs.Count -eq 0) { $bad.Add($id) }
                else {
                    foreach ($b in $brs) {
                        $bidv = Get-Prop $b 'id'; $bid = if ((Test-Obj $b) -and (Test-Str $bidv)) { $bidv } else { "$id/branch" }
                        $broken = -not (Test-Obj $b) -or -not (Test-Str $bidv)
                        if (-not $broken) {
                            $broken = $bids.Contains($bidv) -or -not (Test-Str (Get-Prop $b 'condition')) -or -not (Test-Str (Get-Prop $b 'expected'))
                            foreach ($k in $apps) { if (-not (Test-In $Spec.branchCoverage (Get-Prop $b $k))) { $broken = $true } }
                            $conf = $false; foreach ($k in $apps) { if (Test-Same (Get-Prop $b $k) 'conflicting') { $conf = $true } }
                            if ($conf -and -not (Test-Str (Get-Prop $b 'risk'))) { $broken = $true }
                            $acc = Get-Arr (Get-Prop $b 'acceptance'); if ($acc.Count -eq 0) { $broken = $true }
                            foreach ($a in $acc) { $hit = $false; foreach ($x in $acs) { if ((Test-Obj $x) -and (Test-Same (Get-Prop $x 'id') $a) -and (Test-In (Get-Arr (Get-Prop $x 'rules')) $rid)) { $hit = $true } }; if (-not $hit) { $broken = $true } }
                        }
                        if ($broken) { $bad.Add($bid); continue }
                        $bids.Add($bidv)
                        $ev = @(); $branchRefs = New-Object System.Collections.ArrayList
                        foreach ($e in (Get-Arr (Get-Prop $b 'evidence'))) {
                            if ($branchRefs.Contains($e)) { continue }; [void]$branchRefs.Add($e)
                            $x = Find-Id $evidence $e
                            if ($null -eq $x) { & $add 'EVIDENCE_UNKNOWN' 1 "$bidv/$(Get-Shown $e)"; continue }
                            if ((Test-In $excluded (Get-Prop $x 'system')) -or (& $isHist $x) -or -not (Test-Same (Get-Prop $x 'level') 'code') -or ((Get-Prop $x 'stale') -is [bool] -and (Get-Prop $x 'stale'))) { continue }
                            $kind = Get-Prop $x 'kind'
                            if (Test-Same $kind 'repo-file') { $h = & $fileOf (Get-Prop $x 'source'); $recorded = Get-Prop $x 'sha256'; if ($null -eq $h -or (($recorded -is [string]) -and -not (Test-Same $recorded.ToLowerInvariant() $h))) { continue } }
                            if ((Test-Same $kind 'external') -and -not (Test-Str (Get-Prop $x 'revision'))) { continue }
                            $ev += , $x
                        }
                        foreach ($k in $apps) { if ((Test-Same (Get-Prop $b $k) 'covered') -and -not (Test-BranchProven $k $ev $scripted $reg)) { & $add 'BRANCH_COVERAGE_UNPROVEN' 1 "$bidv/$k" } }
                        foreach ($k in $apps) { $cv = Get-Prop $b $k; if (-not (Test-Same $cv 'covered') -and -not (Test-Same $cv 'not-applicable')) { $key = "${k}:$bidv"; if (-not $open.Contains($key)) { $open.Add($key) } } }
                    }
                }
                foreach ($x in $bad) { & $add 'BRANCH_INCOMPLETE' 0 $x }
                $hasDab = Test-Has $r 'dab'
                if (Test-Same $action 'reuse') { foreach ($x in $open) { $k = $x.Substring(0, $x.IndexOf(':')); if ((Test-Same $k 'cdms') -or (Test-Same $k 'ui') -or -not $hasDab) { & $add 'BRANCH_NOT_COVERED' 1 ($x.Substring($x.IndexOf(':') + 1) + '/' + $k) } } }
                $dabv = Get-Prop $r 'dab'
                if ((Test-Obj $dabv) -and (Test-Same (Get-Prop $dabv 'status') 'implemented')) { foreach ($x in $open) { if ($x.StartsWith('dab:', [System.StringComparison]::Ordinal)) { & $add 'DAB_BRANCH_GAP' 1 $x.Substring(4) } } }
            }
            $rt = Get-Prop $r 'rule'
            if (Test-Str $rt) { $t = Get-Norm $rt; if ($ruleTexts.Contains($t)) { & $add 'RULE_DUPLICATE' 3 $id } else { $ruleTexts.Add($t) } }
            foreach ($d in (Get-Arr (Get-Prop $r 'dependencies'))) { if ($null -eq (Find-Id $deps $d)) { & $add 'DEPENDENCY_UNKNOWN' 0 "$id/$(Get-Shown $d)" } }
            $d = Find-Id $decisions (Get-Prop $r 'decisionRef')
            if (-not (Test-Same (Get-Prop $r 'decision') 'confirmed') -or $null -eq $d -or -not (Test-Same (Get-Prop $d 'status') 'approved')) { & $add 'DECISION_PENDING' 2 $id }
            $need = if ($cov -is [array] -and $cov.Count) { $cov } else { @('positive', 'negative') }
            foreach ($t in $need) {
                $hit = $false
                foreach ($a in $acs) { if ((Test-Obj $a) -and (Test-In (Get-Arr (Get-Prop $a 'rules')) $rid) -and (Test-Same (Get-Prop $a 'type') $t)) { $hit = $true; break } }
                if (-not $hit) { & $add 'MISSING_COVERAGE' 0 "$id/$t" }
            }
        }
        for ($i = 0; $i -lt $acs.Count; $i++) {
            $a = $acs[$i]; $aid = Get-Prop $a 'id'; $id = if ((Test-Obj $a) -and (Test-Str $aid)) { $aid } else { "criterion $($i + 1)" }
            $links = Get-Arr (Get-Prop $a 'rules')
            if (-not (Test-Obj $a) -or -not (Test-Str $aid) -or -not (Test-Rev (Get-Prop $a 'rev')) -or -not (Test-In $Spec.acTypes (Get-Prop $a 'type')) -or -not $links.Count) { & $add 'AC_INCOMPLETE' 0 $id; continue }
            if (-not (Test-Meaningful (Get-Prop $a 'criterion'))) { & $add 'CONTENT_MISSING' 0 $id }
            foreach ($l in $links) { if (-not (Test-In $ruleIds $l)) { & $add 'AC_UNKNOWN_RULE' 0 "$id/$(Get-Shown $l)" } }
        }
        for ($i = 0; $i -lt $evidence.Count; $i++) {
            $e = $evidence[$i]; $eid = Get-Prop $e 'id'; $id = if ((Test-Obj $e) -and (Test-Str $eid)) { $eid } else { "evidence $($i + 1)" }
            $kind = Get-Prop $e 'kind'; $src = Get-Prop $e 'source'
            if (-not (Test-Obj $e) -or -not (Test-Str $eid) -or -not (Test-In $Spec.evidenceLevels (Get-Prop $e 'level')) -or -not (Test-In $Spec.evidenceKinds $kind) -or -not (Test-Str $src) -or -not (Test-Str (Get-Prop $e 'location')) -or -not (Test-Str (Get-Prop $e 'summary')) -or ((Test-Has $e 'system') -and -not (Test-In $Spec.evidenceSystems (Get-Prop $e 'system'))) -or ((Test-Has $e 'component') -and -not (Test-In $Spec.evidenceComponents (Get-Prop $e 'component'))) -or ((Test-Same $kind 'repo-file') -and -not (Test-SafePath $src)) -or ((Test-Same $kind 'external') -and -not (Test-Str (Get-Prop $e 'revision')))) { & $add 'EVIDENCE_INCOMPLETE' 1 $id; continue }
            $stale = Get-Prop $e 'stale'; if (($stale -is [bool]) -and $stale) { & $add 'EVIDENCE_STALE' 1 $id }
            if (Test-Same $kind 'repo-file') {
                $h = & $fileOf $src; $recorded = Get-Prop $e 'sha256'
                if ($null -eq $h) { & $add 'EVIDENCE_SOURCE_MISSING' 1 $id } elseif (($recorded -is [string]) -and -not (Test-Same $recorded.ToLowerInvariant() $h)) { & $add 'EVIDENCE_CHANGED' 1 $id }
            }
        }
        for ($i = 0; $i -lt $actors.Count; $i++) {
            $a = $actors[$i]; $id = if ((Test-Obj $a) -and (Test-Str (Get-Prop $a 'id'))) { $a.id } else { "actor $($i + 1)" }
            if (-not (Test-Obj $a) -or -not (Test-Str (Get-Prop $a 'role')) -or -not (Test-Str (Get-Prop $a 'unauthorizedBehavior')) -or -not (Test-In $Spec.identities (Get-Prop $a 'identity'))) { & $add 'ACTOR_INCOMPLETE' 0 $id }
            elseif (Test-Same $a.identity 'unknown') { & $add 'IDENTITY_UNKNOWN' 1 $id }
        }
        $qs = $Lists['questions']
        $asked = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt $qs.Count; $i++) {
            $q = $qs[$i]; $qst = Get-Prop $q 'status'
            if (-not (Test-Obj $q) -or (Test-Same $qst 'superseded')) { continue }
            $id = if (Test-Str (Get-Prop $q 'id')) { $q.id } else { "question $($i + 1)" }; $cap = if (Test-Same (Get-Prop $q 'owner') 'technical') { 1 } else { 2 }
            $qt = Get-Prop $q 'question'
            if (Test-Str $qt) { $t = Get-Norm $qt; if ($asked.Contains($t)) { & $add 'QUESTION_DUPLICATE' 3 $id } else { $asked.Add($t) } }
            $b = Get-Prop $q 'blocking'
            if (-not ($b -is [bool]) -or -not $b) { continue }
            if (-not (Test-In $Spec.questionResolved $qst)) { & $add 'BLOCKING_QUESTION' $cap $id }
            elseif (-not (Test-Str (Get-Prop $q 'resolution')) -or ($cap -eq 2 -and -not (Test-Same $qst 'not-applicable') -and -not (Test-Same (Get-Prop (Find-Id $decisions (Get-Prop $q 'decisionRef')) 'status') 'approved'))) { & $add 'QUESTION_UNSUPPORTED' $cap $id }
        }
        $as = $Lists['assumptions']
        for ($i = 0; $i -lt $as.Count; $i++) {
            $a = $as[$i]; $c = Get-Prop $a 'changesBehavior'
            if ((Test-Obj $a) -and ($c -is [bool]) -and $c -and -not (Test-Same (Get-Prop $a 'status') 'resolved')) { & $add 'OPEN_ASSUMPTION' 2 $(if (Test-Str (Get-Prop $a 'id')) { $a.id } else { "assumption $($i + 1)" }) }
        }
        for ($i = 0; $i -lt $decisions.Count; $i++) {
            $d = $decisions[$i]; if (-not (Test-Obj $d)) { continue }
            $id = if (Test-Str (Get-Prop $d 'id')) { $d.id } else { "decision $($i + 1)" }
            if (-not (Test-Same (Get-Prop $d 'pbi') $pbi)) { & $add 'FOREIGN_DECISION' 2 $id }
            if ((Test-Same (Get-Prop $d 'status') 'approved') -and -not (Test-Str (Get-Prop $d 'evidence'))) { & $add 'DECISION_NO_EVIDENCE' 2 $id }
            if (Test-Same (Get-Prop $d 'status') 'proposed') { & $add 'DECISION_PROPOSED' 2 $id }
            $sup = Get-Prop $d 'supersedes'
            if ((Test-Str $sup) -and -not (Test-Same (Get-Prop (Find-Id $decisions $sup) 'status') 'superseded')) { & $add 'DECISION_SUPERSEDES_INVALID' 2 $id }
            if ((Test-Str (Get-Prop $d 'id')) -and (($null -eq $docs.decisionLog) -or -not (Test-HasId $docs.decisionLog $d.id))) { & $add 'DECISION_NOT_LOGGED' 3 $id }
        }
        for ($i = 0; $i -lt $deps.Count; $i++) {
            $d = $deps[$i]
            if (-not (Test-Obj $d) -or -not (Test-Str (Get-Prop $d 'id')) -or -not (Test-Str (Get-Prop $d 'repository')) -or -not (Test-Str (Get-Prop $d 'responsibility'))) { & $add 'DEPENDENCY_INCOMPLETE' 0 $(if ((Test-Obj $d) -and (Test-Str (Get-Prop $d 'id'))) { $d.id } else { "dependency $($i + 1)" }) }
        }
        $f = Get-Prop $state 'feasibility'
        if (-not (Test-Obj $f) -or -not (Test-Same (Get-Prop $f 'status') 'reviewed') -or -not (Test-Str (Get-Prop $f 'evidence'))) { & $add 'FEASIBILITY_PENDING' 1 $pbi }
        # Approval basis: a fingerprint per record in each scope; local evidence files are bound by their content hash.
        $part = @{}
        foreach ($n in $Spec.lists) {
            $list = New-Object System.Collections.ArrayList; $items = $Lists[$n]
            for ($i = 0; $i -lt $items.Count; $i++) {
                $x = $items[$i]; $key = if ((Test-Obj $x) -and (Test-Str (Get-Prop $x 'id'))) { $x.id } else { $n + '[' + $i + ']' }
                $target = $x
                if ($n -ceq 'evidence') { $target = New-Map; $target['record'] = $x; $target['file'] = $(if ((Test-Obj $x) -and (Test-Same (Get-Prop $x 'kind') 'repo-file')) { & $fileOf (Get-Prop $x 'source') } else { $null }) }
                [void]$list.Add(@($key, (Get-Fp $target)))
            }
            $part[$n] = $list
        }
        foreach ($n in @('paths', 'feasibility')) { $part[$n] = @(, @($n, (Get-Fp (Get-Prop $state $n)))) }
        # Only fingerprinted when recorded, so approvals given before 4.0 stay valid.
        # Assigned inside the branches: an if-expression would unroll the one-pair array.
        if (Test-Has $state 'evidenceScope') { $part['evidenceScope'] = @(, @('evidenceScope', (Get-Fp (Get-Prop $state 'evidenceScope')))) } else { $part['evidenceScope'] = @() }
        if (Test-Str $docs['reviewedContent']) { $part['reviewedContent'] = @(, @('reviewedContent', $docs['reviewedContent'])) } else { $part['reviewedContent'] = @() }
        foreach ($k in $Spec.approvals) {
            $m = New-Map; foreach ($n in $Spec.scopes.$k) { foreach ($pair in $part[$n]) { $m[$pair[0]] = $pair[1] } }
            $keys = [string[]]@($m.Keys); [array]::Sort($keys, [System.StringComparer]::Ordinal)
            $basis = New-Map; foreach ($key in $keys) { $basis[$key] = $m[$key] }
            $review[$k] = [ordered]@{ fingerprint = (Get-Fp $basis); basis = $basis }
        }
        foreach ($k in $Spec.approvals) {
            $a = Get-Prop (Get-Prop $state 'approvals') $k
            if (-not (Test-Obj $a) -or -not (Test-Same (Get-Prop $a 'status') 'approved') -or -not (Test-Str (Get-Prop $a 'by')) -or -not (Test-Str (Get-Prop $a 'at')) -or -not (Test-Str (Get-Prop $a 'evidence'))) { if (@($Spec.requiredApprovals) -contains $k) { & $add 'APPROVAL_PENDING' 3 $k }; continue }
            $b = Get-Prop $a 'basis'; $bad = -not (Test-Obj $b) -or -not @($b.PSObject.Properties).Count
            if (-not $bad) { foreach ($p in $b.PSObject.Properties) { $pattern = if ($p.Name -ceq 'reviewedContent') { '\A[0-9a-f]{64}\z' } else { '\A[0-9a-f]{16}\z' }; if (-not ($p.Value -is [string]) -or $p.Value -cnotmatch $pattern) { $bad = $true } } }
            if ($bad) { & $add 'APPROVAL_UNBOUND' 3 $k; continue }
            $cur = $review[$k].basis
            if ($k -ceq 'user' -and -not (Test-Has $b 'reviewedContent')) { $legacy = New-Map; foreach ($key in $cur.Keys) { if ($key -cne 'reviewedContent') { $legacy[$key] = $cur[$key] } }; $cur = $legacy }
            $changed = New-Object System.Collections.Generic.List[string]; $added = New-Object System.Collections.Generic.List[string]; $removed = New-Object System.Collections.Generic.List[string]
            foreach ($key in $cur.Keys) { if (-not (Test-Has $b $key)) { $added.Add($key) } elseif (-not (Test-Same (Get-Prop $b $key) $cur[$key])) { $changed.Add($key) } }
            foreach ($key in (Get-Keys $b)) { if (-not $cur.ContainsKey($key)) { $removed.Add($key) } }
            $diff = @(); foreach ($w in @(@('changed', $changed), @('added', $added), @('removed', $removed))) { if ($w[1].Count) { $diff += $w[0] + ' ' + ($w[1] -join ', ') } }
            if ($diff.Count) { & $add 'APPROVAL_STALE' 3 ("${k}: " + ($diff -join '; ')) }
        }
        # $pre names an application-specific final document in the issue reference.
        $checkDoc = {
            param($doc, $pre)
            $m = [regex]::Match($doc, '(?m)^Status:\s*(.+?)\s*$')
            if (-not $m.Success -or -not (Test-Same $m.Groups[1].Value (Get-Prop $state 'status'))) { & $add 'DOC_STATUS_MISMATCH' 3 ($pre + $(if ($m.Success) { $m.Groups[1].Value } else { '(no Status line)' })) }
            $n = Get-DocNorm $doc; $done = New-Object System.Collections.Generic.List[string]
            $pairs = @(); foreach ($x in $rules) { $pairs += , @($x, (Get-Prop $x 'rule')) }; foreach ($x in $acs) { $pairs += , @($x, (Get-Prop $x 'criterion')) }; foreach ($x in $deps) { $pairs += , @($x, $null) }
            foreach ($pair in $pairs) {
                $x = $pair[0]; $xid = Get-Prop $x 'id'
                if (-not (Test-Obj $x) -or -not (Test-Str $xid) -or $done.Contains($xid)) { continue }; $done.Add($xid)
                if (-not (Test-HasId $doc $xid)) { & $add 'DOC_MISSING_ID' 3 ($pre + $xid) }
                elseif ((Test-Meaningful $pair[1]) -and -not $n.Contains((Get-DocNorm $pair[1]))) { & $add 'DOC_CONTENT_MISMATCH' 3 ($pre + $xid) }
            }
        }
        $doc = if ($null -ne $docs.refined) { $docs.refined } else { $docs.draft }
        if ($null -eq $doc) { & $add 'DOC_MISSING' 0 $pbi } else { & $checkDoc $doc '' }
        foreach ($key in (Get-FinalKeys)) {
            $fd = Get-Prop $Spec.finalDocs $key
            if ($null -ne $docs[$key]) { if (-not $applies.Contains($fd[0])) { & $add 'DOC_OUT_OF_SCOPE' 3 $fd[1] }; & $checkDoc $docs[$key] ($fd[1] + '/') }
        }
    }
    $capOf = { $c = 4; foreach ($x in $issues) { $j = [array]::IndexOf($S, $x.cap); if ($j -lt $c) { $c = $j } }; $c }
    if ($valid -and (& $capOf) -lt 4) {
        if ($null -ne $docs.refined) { & $add 'FINAL_WITHOUT_APPROVAL' 3 $pbi }
        foreach ($key in (Get-FinalKeys)) { if ($null -ne $docs[$key]) { & $add 'FINAL_WITHOUT_APPROVAL' 3 (Get-Prop $Spec.finalDocs $key)[1] } }
    }
    $claimed = if ($valid -and (Test-In $S (Get-Prop $state 'status'))) { $state.status } else { '' }
    if ($claimed -and [array]::IndexOf($S, $claimed) -gt (& $capOf)) { & $add 'STATUS_OVERCLAIMED' 3 $claimed }
    $computed = $S[(& $capOf)]
    return [ordered]@{ schemaVersion = 2; pbi = $pbi; claimedStatus = $claimed; computedStatus = $computed; finalAllowed = ($computed -ceq 'Development-Ready'); issues = @($issues); review = $review; reviewedContent = $docs['reviewedContent'] }
}
# The development target of a 5.0 intake (pbi.json with repositories); 4.x PBIs keep the 4.x path rules (same as applicationOf in core.js).
function Get-Application([string]$folder) {
    $raw = Read-Text "$folder/pbi.json"; if ($null -eq $raw) { return $null }
    try { $p = $raw | ConvertFrom-Json } catch { return $null }
    # Read the property directly: a function return would unroll an empty array to `$null.
    $a = Get-Prop $p 'application'; $repos = if (Test-Obj $p) { $p.PSObject.Properties['repositories'] } else { $null }
    if (($a -is [string]) -and $null -ne $repos -and ($repos.Value -is [array])) { return $a }; return $null
}
function Invoke-CheckPbi {
    if (-not $Pbi) { throw 'Use -Pbi <folder name> (the folder under playbook/pbis).' }
    $folder = $Pbi.Replace('\', '/').TrimEnd('/')
    if (-not $folder.StartsWith('playbook/pbis/', $Ordinal)) { $folder = 'playbook/pbis/' + $folder }
    if (-not (Test-SafePath $folder) -or $folder -notmatch '^playbook/pbis/[^/]+$') { throw 'Select one PBI folder under playbook/pbis.' }
    $raw = Read-Text "$folder/pbi-state.json"; $state = $null
    if ($null -ne $raw) { try { $state = $raw | ConvertFrom-Json } catch { $state = $null } }
    $files = New-Map
    foreach ($e in (Get-Arr (Get-Prop $state 'evidence'))) {
        $src = Get-Prop $e 'source'
        if ((Test-Obj $e) -and (Test-Same (Get-Prop $e 'kind') 'repo-file') -and (Test-SafePath $src) -and -not $files.ContainsKey($src)) {
            $full = Get-Full $src; $files[$src] = if ([System.IO.File]::Exists($full)) { Get-Hash ([System.IO.File]::ReadAllBytes($full)) } else { $null }
        }
    }
    # 4.0 names are still read when the 4.1 names are absent (same as checkPbi in core.js).
    $reviewedContent = Get-ReviewFingerprint $folder $files
    $docs = @{ request = Read-Text "$folder/REQUEST.md"; draft = Read-Text "$folder/DRAFT-PBI.md"; refined = Read-Text "$folder/REFINED-PBI.md"; cdmsRefined = Read-Text "$folder/PBI-CDMS.md"; dabRefined = Read-Text "$folder/PBI-DAB.md"; uiRefined = Read-Text "$folder/PBI-UI.md"; application = (Get-Application $folder); decisionLog = Read-Text "$folder/DECISION-LOG.md"; files = $files; reviewedContent = $reviewedContent }
    foreach ($pair in @(@('cdmsRefined', 'CDMS-REFINED-PBI.md'), @('dabRefined', 'DAB-REFINED-PBI.md'))) { if ($null -eq $docs[$pair[0]]) { $docs[$pair[0]] = Read-Text "$folder/$($pair[1])" } }
    $r = Get-Readiness $state $docs $folder.Split('/')[-1]
    if (-not (Test-SameText (Read-Text "$folder/pbi-state.json") $raw) -or -not (Test-Same (Get-ReviewFingerprint $folder) $reviewedContent)) { throw 'PBI changed while it was being reviewed. Reload the review and try again.' }
    if ($Json) { [Console]::Out.WriteLine((ConvertTo-Json -InputObject $r -Depth 6 -Compress)) }
    else {
        Write-Host "Readiness for $($r.pbi)"; Write-Host "Computed status: $($r.computedStatus)$(if ($r.claimedStatus) { " (claimed: $($r.claimedStatus))" })"
        Write-Host "Final REFINED-PBI.md allowed: $(if ($r.finalAllowed) { 'yes' } else { 'no' })"
        if ($r.issues.Count) { foreach ($x in $r.issues) { Write-Host "[$($x.cap)] $($x.code) $($x.ref): $($x.message)" } } else { Write-Host 'No issues found.' }
        if ([array]::IndexOf(@($Bundle.readiness.statuses), $r.computedStatus) -ge 3) {
            Write-Host ''; Write-Host 'Approval basis: give the agent the block for each approval it records, unchanged.'
            foreach ($k in $r.review.Keys) { Write-Host "$k (fingerprint $($r.review[$k].fingerprint)): $(ConvertTo-Json -InputObject $r.review[$k].basis -Compress)" }
        }
        Write-Host 'This checks completeness and consistency only, not business correctness or who approved.'
    }
    return [bool]$r.finalAllowed
}

# ---- Evidence fingerprints: mirrors refreshEvidence() in core.js ----
function Invoke-RefreshEvidence {
    $out = [ordered]@{ checked = 0; fingerprinted = @(); stale = @(); skipped = @(); written = $false }
    $raw = Read-Text $Bundle.knowledgeIndex
    if ($null -ne $raw) {
        try { $index = $raw | ConvertFrom-Json } catch { throw "$($Bundle.knowledgeIndex) is not valid JSON. Fix it before refreshing." }
        if (-not (Test-Obj $index) -or -not (Test-One (Get-Prop $index 'schemaVersion')) -or -not ((Get-Prop $index 'entries') -is [array])) { throw "Unsupported $($Bundle.knowledgeIndex); expected schemaVersion 1 with an entries list." }
        $changed = $false; $hashes = New-Map
        foreach ($e in $index.entries) {
            if (-not (Test-Obj $e)) { continue }
            $id = if ((Get-Prop $e 'id') -is [string]) { $e.id } elseif ((Get-Prop $e 'path') -is [string]) { $e.path } else { '' }
            # shortcut: only paths inside the selected repository can be hashed; external sources need the revision recorded by the agent.
            $p = Get-Prop $e 'path'
            if (-not (Test-SafePath $p)) { $out.skipped += $id; continue }
            $out.checked = $out.checked + 1
            if ($hashes.ContainsKey($p)) { $h = $hashes[$p] }
            else {
                $full = Get-Full $p
                if ([System.IO.Directory]::Exists($full)) { throw "Evidence path is a folder, not a file: $p" }
                $h = if ([System.IO.File]::Exists($full)) { Get-Hash ([System.IO.File]::ReadAllBytes($full)) } else { $null }
                $hashes[$p] = $h
            }
            $isStale = ((Get-Prop $e 'stale') -is [bool]) -and (Get-Prop $e 'stale')
            if ($null -eq $h) {
                if (-not $isStale -or -not (Test-Same (Get-Prop $e 'staleReason') 'missing')) { Set-Prop $e 'stale' $true; Set-Prop $e 'staleReason' 'missing'; $changed = $true }
                $out.stale += $id
            }
            elseif (-not ((Get-Prop $e 'sha256') -is [string])) { Set-Prop $e 'sha256' $h; $changed = $true; $out.fingerprinted += $id; if ($isStale) { $out.stale += $id } }
            elseif (-not (Test-Same $e.sha256 $h)) { Set-Prop $e 'stale' $true; Set-Prop $e 'staleReason' 'changed'; Set-Prop $e 'sha256' $h; $changed = $true; $out.stale += $id }
            elseif ($isStale) { $out.stale += $id }
        }
        if ($changed) { Write-Text $Bundle.knowledgeIndex ((ConvertTo-Json -InputObject $index -Depth 100) + "`n"); $out.written = $true }
    }
    if ($Json) { [Console]::Out.WriteLine((ConvertTo-Json -InputObject $out -Depth 4 -Compress)) }
    elseif ($null -eq $raw) { Write-Host "No evidence index found at $($Bundle.knowledgeIndex). The agent creates it when it records reusable knowledge." }
    else {
        Write-Host "Checked $($out.checked) evidence entries. Newly fingerprinted: $(@($out.fingerprinted).Count). Stale: $(if (@($out.stale).Count) { $out.stale -join ', ' } else { 'none' })."
        if (@($out.skipped).Count) { Write-Host "Outside this repository (not fingerprinted): $($out.skipped -join ', ')" }
    }
    return -not @($out.stale).Count
}

# ---- Settings ----
function Read-Choice([string]$prompt, [string]$default) { $a = Read-Host "$prompt [$default]"; if ([string]::IsNullOrWhiteSpace($a)) { return $default }; return $a.Trim() }
function Read-YesNo([string]$prompt) { return (Read-Host "$prompt [y/N]") -match '^(y|yes)$' }
# 'Name=path' entries (-OtherSource or the prompt); blank entries are ignored, so an empty value clears the list.
function ConvertFrom-OtherSource([string[]]$items) {
    # ';' also separates entries, because powershell.exe -File passes a single string.
    return @($items -split ';' | Where-Object { $_ -and $_.Trim() } | ForEach-Object {
            $i = $_.IndexOf('='); if ($i -lt 1) { throw "Write each other repository as Name=path: $_" }
            [pscustomobject]@{ name = $_.Substring(0, $i).Trim(); path = $_.Substring($i + 1).Trim() } })
}
function Get-ConfigInput([bool]$existingOnly) {
    $raw = Read-Text "$($Bundle.base)/config.json"
    $in = @{ schemaVersion = $null; projectName = (Split-Path -Leaf $script:Repo); ide = 'visualstudio'; role = 'legacy'; includeReferences = $false; sources = @{ legacy = ''; dab = ''; cdms = ''; ui = '' }; others = @() }
    if ($null -ne $raw) {
        try { $old = $raw | ConvertFrom-Json } catch { throw "The existing $($Bundle.base)/config.json is not valid JSON. Fix or remove it, then rerun." }
        $in.schemaVersion = Get-Prop $old 'schemaVersion'
        foreach ($k in 'projectName', 'ide', 'role', 'includeReferences') { if (Test-Has $old $k) { $in[$k] = $old.$k } }
        # As in the wizard, '.' (this repository) is re-derived from the role.
        foreach ($k in $SourceKeys) { $v = Get-Prop (Get-Prop $old 'sources') $k; $in.sources[$k] = if ($v -is [string] -and $v -cne '.') { $v } else { '' } }
        $list = Get-Prop $old 'others'
        if ($list -is [array]) { foreach ($o in $list) { $in.others += [pscustomobject]@{ name = Get-Prop $o 'name'; path = Get-Prop $o 'path' } } }
    }
    elseif ($existingOnly) { throw "No $($Bundle.base)/config.json found. Run Install first." }
    if ($existingOnly) {
        if (@('ProjectName', 'Ide', 'Role', 'LegacySource', 'DabSource', 'CdmsSource', 'UiSource', 'OtherSource', 'NoReferences', 'IncludeReferences' | Where-Object { $script:Bound.ContainsKey($_) }).Count) { Write-Warning 'Repair uses the installed config.json; setting parameters were ignored. Use Install to change settings.' }
        return $in
    }
    if ($script:Bound.ContainsKey('ProjectName')) { $in.projectName = $ProjectName }
    if ($script:Bound.ContainsKey('Ide')) { $in.ide = $Ide }
    if ($script:Bound.ContainsKey('Role')) { $in.role = $Role }
    if ($script:Bound.ContainsKey('NoReferences')) { $in.includeReferences = -not $NoReferences }
    if ($script:Bound.ContainsKey('IncludeReferences')) { $in.includeReferences = [bool]$IncludeReferences }
    if ($script:Bound.ContainsKey('LegacySource')) { $in.sources.legacy = $LegacySource }
    if ($script:Bound.ContainsKey('DabSource')) { $in.sources.dab = $DabSource }
    if ($script:Bound.ContainsKey('CdmsSource')) { $in.sources.cdms = $CdmsSource }
    if ($script:Bound.ContainsKey('UiSource')) { $in.sources.ui = $UiSource }
    if ($script:Bound.ContainsKey('OtherSource')) { $in.others = ConvertFrom-OtherSource $OtherSource }
    if ($Interactive) {
        $in.projectName = Read-Choice 'Project name' $in.projectName
        $in.ide = Read-Choice 'Editor: visualstudio or vscode' $in.ide
        $in.role = Read-Choice 'This repository is: legacy, dab, cdms, ui or other' $in.role
        foreach ($k in $SourceKeys) { if ($in.role -cne $k) { $in.sources[$k] = Read-Choice "Optional $k repository path, relative to this repository (blank if none)" $in.sources[$k] } }
        $in.others = ConvertFrom-OtherSource ((Read-Choice 'Other reference repositories as Name=path, separated by ; (blank if none)' (@($in.others | ForEach-Object { "$($_.name)=$($_.path)" }) -join ';')) -split ';')
        $in.includeReferences = (Read-Choice 'Also install the older ColorDMS analysis documents as optional background (not needed)? y/n' $(if ($in.includeReferences) { 'y' } else { 'n' })) -match '^(y|yes)$'
    }
    return $in
}
function Select-Repo {
    if (-not $Interactive) { $path = $RepoPath }
    else {
        $path = $null
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
            $dialog.Description = 'Select the application repository root'
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $path = $dialog.SelectedPath } else { throw 'Cancelled. Nothing was changed.' }
        }
        catch [System.Management.Automation.RuntimeException] { if ($_.Exception.Message -like 'Cancelled*') { throw }; $path = Read-Host 'Repository root folder' }
        catch { $path = Read-Host 'Repository root folder' }
    }
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Container)) { throw "Repository folder not found: $path" }
    $script:Repo = (Resolve-Path -LiteralPath $path).ProviderPath
    if (-not (Test-Path -LiteralPath (Join-Path $script:Repo '.git'))) {
        Write-Warning "No .git found in $($script:Repo). Make sure this is the application repository root, not a parent folder or one nested project."
        if ($Interactive -and $Action -in 'Install', 'Repair' -and -not (Read-YesNo 'Continue with this folder?')) { throw 'Cancelled. Nothing was changed.' }
    }
}

# ---- Actions ----
function Invoke-Install([bool]$repair) {
    $htmlPath = Join-Path $PSScriptRoot 'Akzo-SDD-PBI-Builder.html'
    if (-not [System.IO.File]::Exists($htmlPath)) { throw 'Akzo-SDD-PBI-Builder.html is missing next to this script. Use the complete package.' }
    $c = New-Config (Get-ConfigInput $repair)
    $rows = Get-Plan (Get-SetupFiles $c ([System.IO.File]::ReadAllText($htmlPath, $Utf8)))
    Write-Host "Repository: $($script:Repo)"; Write-Host "Agent: $($c.agentName)"
    Show-Plan $rows
    if ($Preview) { Write-Host 'Preview only. No files written.'; return $true }
    $needsUpdate = @($rows | Where-Object { $_.state -ceq 'update' -or $_.state -ceq 'retire' }).Count -gt 0
    $allow = [bool]$AllowUpdates -or $repair
    if ($Interactive) {
        if (@($rows | Where-Object { $_.state -ceq 'conflict' }).Count) { Write-Host 'Resolve the conflicts above, then rerun.'; return $false }
        if (-not (Read-YesNo 'Apply these changes?')) { Write-Host 'Cancelled. Nothing was changed.'; return $true }
        if ($needsUpdate -and -not $allow) { $allow = Read-YesNo 'Allow updates to previously installed files and retirement of unchanged earlier-version files, with backups?' }
    }
    $r = Invoke-Apply $rows $allow
    Write-Host "Setup complete: $($r.written) files saved."
    if ($r.backups.Count) { Write-Host "Backups: $($Bundle.base)/backups/" }
    if ($r.retired.Count) { Write-Host "Retired: $($r.retired -join ', ')" }
    if ($r.kept.Count) { Write-Host "Kept (edited or unowned; review and remove yourself): $($r.kept -join ', ')" -ForegroundColor Yellow }
    Write-Host "Open this repository in $(if ($c.ide -ceq 'vscode') { 'VS Code' } else { 'Visual Studio' }) and select $($c.agentName) in Copilot Chat."
    return $true
}
function Invoke-Verify {
    $m = Read-Manifest
    if ($null -eq $m) { throw 'No PBI Builder installation record found in this folder.' }
    $bad = 0
    foreach ($p in $m.files.PSObject.Properties) {
        $t = Read-Text $p.Name
        $state = if ($null -eq $t) { 'MISSING' } elseif (Test-Same (Get-TextHash $t) $p.Value) { 'OK' } else { 'CHANGED' }
        if ($state -cne 'OK') { $bad++ }
        Write-Host ('{0,-8} {1}' -f $state, $p.Name)
    }
    Write-Host "Installed package: $($m.packageVersion). This package: $($Bundle.packageVersion)."
    if ($bad) { Write-Host 'Review missing/changed files. Repair restores missing and unchanged managed files; changed files are never overwritten.' } else { Write-Host 'All recorded files match.' }
    Write-Host 'This does not verify Copilot discovery, source access or AI output.'
    return -not $bad
}
function Invoke-Uninstall {
    $m = Read-Manifest
    if ($null -eq $m) { throw 'No PBI Builder installation record found in this folder. Nothing to uninstall.' }
    $c = $null; try { $c = New-Config (Get-ConfigInput $true) } catch { Write-Warning "Installed config.json could not be read; comparison baseline agents are left in place. $($_.Exception.Message)" }
    $protected = @('playbook/pbis/', "$($Bundle.base)/knowledge/", "$($Bundle.base)/backups/")
    $rows = New-Object System.Collections.ArrayList
    foreach ($p in $m.files.PSObject.Properties) {
        if (@($protected | Where-Object { $p.Name.StartsWith($_, $Ordinal) }).Count -or $p.Name -ceq $Bundle.manifest) { continue }
        $t = Read-Text $p.Name; if ($null -eq $t) { continue }
        [void]$rows.Add([pscustomobject]@{ path = $p.Name; before = $t; state = $(if (Test-Same (Get-TextHash $t) $p.Value) { 'remove' } else { 'keep' }) })
    }
    foreach ($b in $Bundle.baselines.PSObject.Properties) {
        $t = Read-Text $b.Value.path; if ($null -eq $t) { continue }
        [void]$rows.Add([pscustomobject]@{ path = $b.Value.path; before = $t; state = $(if ($c -and (Test-SameText $t (Get-BaselineText $c $b.Value))) { 'remove' } else { 'keep' }) })
    }
    [void]$rows.Add([pscustomobject]@{ path = $Bundle.manifest; before = (Read-Text $Bundle.manifest); state = 'remove' })
    foreach ($r in $rows) { Write-Host ('{0,-8} {1}' -f $r.state, $r.path) }
    Write-Host 'Kept always: playbook/pbis/ (PBIs, decisions, history), knowledge notes, backups, and any file edited since installation.'
    if ($Preview) { Write-Host 'Preview only. No files removed.'; return $true }
    if ($Interactive -and -not (Read-YesNo 'Remove the files marked remove (backed up first)?')) { Write-Host 'Cancelled. Nothing was changed.'; return $true }
    $batch = 'uninstall-' + (Get-Batch); $done = New-Object System.Collections.ArrayList
    $complete = $false; $message = 'Interrupted (for example Ctrl+C).'
    try {
        foreach ($r in @($rows | Where-Object { $_.state -ceq 'remove' })) { Write-Text "$($Bundle.base)/backups/$batch/$($r.path)" $r.before }
        foreach ($r in @($rows | Where-Object { $_.state -ceq 'remove' })) {
            if (-not (Test-SameText (Read-Text $r.path) $r.before)) { throw "A file changed during uninstall: $($r.path)" }
            [void]$done.Add($r); Remove-File $r.path
        }
        $complete = $true
    }
    catch { $message = $_.Exception.Message }
    finally {
        if (-not $complete) { $errors = @(); foreach ($r in $done) { try { Write-Text $r.path $r.before } catch { $errors += $r.path } } }
    }
    if (-not $complete) { throw "Uninstall stopped: $message`n$(if ($errors.Count) { 'Could not restore: ' + ($errors -join ', ') } else { 'Removed files were restored.' })" }
    Write-Host "Uninstalled $($done.Count) files. Backups: $($Bundle.base)/backups/$batch/"
    $kept = @($rows | Where-Object { $_.state -ceq 'keep' })
    if ($kept.Count) { Write-Host "Kept because they were edited: $(($kept | ForEach-Object { $_.path }) -join ', ')" -ForegroundColor Yellow }
    return $true
}

# One JSON line per run in %USERPROFILE%\.akzo-pbi-builder\logs\install.log (paths and outcome only).
$LogFile = Join-Path $env:USERPROFILE '.akzo-pbi-builder\logs\install.log'
function Write-Log([int]$code, [string]$message) {
    try {
        [void][System.IO.Directory]::CreateDirectory((Split-Path $LogFile))
        $line = ConvertTo-Json -Compress ([ordered]@{ time = [DateTime]::UtcNow.ToString('o'); step = $Action; repo = $script:Repo; package = $(if ($Bundle) { $Bundle.packageVersion } else { $null }); exitCode = $code; message = $message })
        [System.IO.File]::AppendAllText($LogFile, $line + "`n", $Utf8)
    }
    catch { }
}
$Bundle = $null
try {
    $Bundle = Read-Bundle
    Select-Repo
    if ($Json) { [Console]::OutputEncoding = $Utf8 }
    $ok = switch ($Action) {
        'Install' { Invoke-Install $false }
        'Repair' { Invoke-Install $true }
        'Verify' { Invoke-Verify }
        'Uninstall' { Invoke-Uninstall }
        'CheckPbi' { Invoke-CheckPbi }
        'RefreshEvidence' { Invoke-RefreshEvidence }
    }
    # 1 is left to PowerShell itself (for example a script blocked by execution policy).
    $code = if ($ok) { 0 } else { 3 }
    Write-Log $code $(if ($ok) { 'ok' } else { 'check failed or nothing written' })
    exit $code
}
catch {
    $m = $_.Exception.Message
    if ($m -match 'Access to the path .* is denied|UnauthorizedAccess') { $m += "`nFix: you need write access to the repository folder. Administrator rights are not needed; choose a clone you own, or close programs that lock these files, then rerun." }
    Write-Log 2 $m
    [Console]::Error.WriteLine("ERROR: $m`nLog: $LogFile")
    exit 2
}
