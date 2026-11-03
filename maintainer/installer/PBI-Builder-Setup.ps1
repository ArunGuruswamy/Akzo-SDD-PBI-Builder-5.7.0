<#
.SYNOPSIS
One-window setup for the Akzo SDD PBI Builder: install, upgrade, repair, verify or
uninstall it in your repositories, and see which ones need an update.

.DESCRIPTION
Started by Install-PBIBuilder.cmd when it is double-clicked. Every action runs
Install-PBIBuilder.ps1 in a child Windows PowerShell under your execution policy,
so its review, conflict protection, backups and rollback apply unchanged.
Install / Upgrade first shows the planned changes and asks before writing; files
you edited are never overwritten. The repositories you add are remembered in
%USERPROFILE%\.akzo-pbi-builder\repositories.txt (paths only).

.EXAMPLE
.\PBI-Builder-Setup.ps1
.EXAMPLE
.\PBI-Builder-Setup.ps1 -NoGui -Action Install -Repo "C:\src\My Repo" -Ide vscode -Role dab
.EXAMPLE
.\PBI-Builder-Setup.ps1 -NoGui -Action Upgrade
#>
[CmdletBinding()]
param(
    [ValidateSet('', 'Install', 'Upgrade', 'Repair', 'Verify', 'Uninstall', 'Status')]
    [string]$Action = '',
    [string[]]$Repo,
    [ValidateSet('visualstudio', 'vscode')][string]$Ide = 'visualstudio',
    [ValidateSet('legacy', 'dab', 'cdms', 'ui', 'other')][string]$Role = 'legacy',
    [switch]$NoGui,
    [string]$HomeRoot = $env:USERPROFILE
)
$ErrorActionPreference = 'Stop'
$Engine = Join-Path $PSScriptRoot 'Install-PBIBuilder.ps1'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$PackageVersion = ([System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'pbi-builder-bundle.json'), $Utf8) | ConvertFrom-Json).packageVersion
$Registry = Join-Path $HomeRoot '.akzo-pbi-builder\repositories.txt'
$Roles = [ordered]@{ legacy = 'Custom (Legacy CRM/XRM)'; dab = 'DAB (GraphQL)'; cdms = 'CDMS'; ui = 'Shared Angular UI'; other = 'Other project / PBI workspace' }

function Get-Repos {
    if (-not (Test-Path -LiteralPath $Registry)) { return @() }
    return @([System.IO.File]::ReadAllLines($Registry, $Utf8) | Where-Object { $_.Trim() } | Sort-Object -Unique)
}
function Save-Repos([string[]]$list) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Registry) | Out-Null
    [System.IO.File]::WriteAllLines($Registry, [string[]]@($list | Where-Object { $_ } | Sort-Object -Unique), $Utf8)
}
function Add-Repo([string]$path) { Save-Repos (@(Get-Repos) + (Resolve-Path -LiteralPath $path).ProviderPath) }
function Remove-Repo([string]$path) { Save-Repos @(Get-Repos | Where-Object { $_ -ne $path }) }
function Get-InstalledVersion([string]$path) {
    $m = Join-Path $path 'playbook\pbi-builder\installed-files.json'
    if (-not (Test-Path -LiteralPath $m)) { return $null }
    try { return ([System.IO.File]::ReadAllText($m, $Utf8) | ConvertFrom-Json).packageVersion } catch { return 'unreadable' }
}
function Get-RepoStatus([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { return 'folder not found' }
    $v = Get-InstalledVersion $path
    if (-not $v) { return 'not installed' }
    if ($v -eq $PackageVersion) { return "$v, up to date" }
    return "$v, update to $PackageVersion available"
}
# The engine's own -RepoPath mode: no prompts, no policy override.
function Invoke-Engine([string]$path, [string[]]$extra) {
    $a = @('-NoProfile', '-NonInteractive', '-File', $Engine, '-RepoPath', $path) + $extra
    $ErrorActionPreference = 'Continue'   # Windows PowerShell 5.1: redirected native stderr must not abort
    $out = & powershell.exe @a 2>&1 | ForEach-Object { "$_" }
    return [pscustomobject]@{ code = $LASTEXITCODE; text = ($out -join [Environment]::NewLine) }
}
# Settings are asked only for a first install; an upgrade keeps the repository's config.json.
function Get-SettingArgs([string]$path, [string]$ide, [string]$role) {
    if (Test-Path -LiteralPath (Join-Path $path 'playbook\pbi-builder\config.json')) { return @() }
    return @('-Ide', $ide, '-Role', $role)
}
# Preview, then ask, then apply with backups. Returns the log text and whether anything failed.
function Invoke-InstallFlow([string]$path, [string]$ide, [string]$role, [scriptblock]$confirm, [string[]]$extra = @()) {
    $settings = @(Get-SettingArgs $path $ide $role) + $extra
    $p = Invoke-Engine $path ($settings + '-Preview')
    if ($p.code -ne 0) { return [pscustomobject]@{ ok = $false; text = $p.text } }
    if ($p.text -match '(?m)^conflict\s') { return [pscustomobject]@{ ok = $false; text = $p.text + "`r`nNothing was written: files you edited differ from the installed record. Restore or move them, then try again." } }
    if ($p.text -notmatch '(?m)^(create|update|retire)\s') { return [pscustomobject]@{ ok = $true; text = $p.text + "`r`nAlready up to date. Nothing to write." } }
    if (-not (& $confirm $p.text)) { return [pscustomobject]@{ ok = $true; text = $p.text + "`r`nCancelled. Nothing was changed." } }
    $r = Invoke-Engine $path ($settings + '-AllowUpdates')
    if ($r.code -eq 0) { Add-Repo $path }
    return [pscustomobject]@{ ok = ($r.code -eq 0); text = $r.text }
}
function Get-UpgradeTargets { return @(Get-Repos | Where-Object { $v = Get-InstalledVersion $_; $v -and $v -ne $PackageVersion }) }

if ($NoGui) {
    if (-not $Action) { throw '-NoGui needs -Action Install, Upgrade, Repair, Verify, Uninstall or Status.' }
    $targets = if ($Repo) { $Repo } elseif ($Action -eq 'Upgrade') { Get-UpgradeTargets } else { Get-Repos }
    $failed = 0
    if ($Action -eq 'Status') { foreach ($t in Get-Repos) { Write-Output "$t : $(Get-RepoStatus $t)" }; exit 0 }
    foreach ($t in $targets) {
        Write-Output "== $Action $t"
        switch ($Action) {
            { $_ -in 'Install', 'Upgrade' } { $r = Invoke-InstallFlow $t $Ide $Role { $true }; Write-Output $r.text; if (-not $r.ok) { $failed++ } }
            'Uninstall' { $r = Invoke-Engine $t @('-Action', 'Uninstall'); Write-Output $r.text; if ($r.code -eq 0) { Remove-Repo $t } else { $failed++ } }
            default { $r = Invoke-Engine $t @('-Action', $Action); Write-Output $r.text; if ($r.code -ne 0) { $failed++ } }
        }
    }
    if (-not @($targets).Count) { Write-Output 'No repositories to process.' }
    exit $(if ($failed) { 3 } else { 0 })
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object System.Windows.Forms.Form -Property @{ Text = "Akzo SDD PBI Builder $PackageVersion - Setup"; Width = 800; Height = 600; StartPosition = 'CenterScreen'; FormBorderStyle = 'FixedDialog'; MaximizeBox = $false }
$info = New-Object System.Windows.Forms.Label -Property @{ Left = 12; Top = 10; Width = 760; Height = 34; Font = New-Object System.Drawing.Font('Segoe UI', 9) }
$info.Text = "This package: $PackageVersion. Install the PBI Builder into each repository you analyse; Upgrade all updates every listed repository that has an older version.`nFiles you edited are never overwritten; replaced files are backed up in playbook\pbi-builder\backups\."
$listLabel = New-Object System.Windows.Forms.Label -Property @{ Left = 12; Top = 50; Width = 400; Text = 'Repositories (installed version):' }
$list = New-Object System.Windows.Forms.ListBox -Property @{ Left = 12; Top = 72; Width = 620; Height = 110 }
$add = New-Object System.Windows.Forms.Button -Property @{ Left = 642; Top = 72; Width = 130; Height = 30; Text = 'Add repository...' }
$addPath = New-Object System.Windows.Forms.Button -Property @{ Left = 642; Top = 108; Width = 130; Height = 30; Text = 'Add by path...' }
$forget = New-Object System.Windows.Forms.Button -Property @{ Left = 642; Top = 144; Width = 130; Height = 30; Text = 'Remove from list' }
$sourcesButton = New-Object System.Windows.Forms.Button -Property @{ Left = 642; Top = 180; Width = 130; Height = 30; Text = 'Repair / configure...' }
$ideLabel = New-Object System.Windows.Forms.Label -Property @{ Left = 12; Top = 222; Width = 200; Text = 'For a first install - Editor:' }
$ideBox = New-Object System.Windows.Forms.ComboBox -Property @{ Left = 215; Top = 219; Width = 170; DropDownStyle = 'DropDownList' }
[void]$ideBox.Items.AddRange(@('Visual Studio 2026', 'VS Code')); $ideBox.SelectedIndex = $(if ($Ide -eq 'vscode') { 1 } else { 0 })
$roleLabel = New-Object System.Windows.Forms.Label -Property @{ Left = 400; Top = 222; Width = 120; Text = 'Repository is:' }
$roleBox = New-Object System.Windows.Forms.ComboBox -Property @{ Left = 520; Top = 219; Width = 252; DropDownStyle = 'DropDownList' }
[void]$roleBox.Items.AddRange(@($Roles.Values)); $roleBox.SelectedIndex = @($Roles.Keys).IndexOf($Role)
$buttons = foreach ($b in 'Install / Upgrade', 'Upgrade all', 'Repair', 'Verify', 'Uninstall', 'Close') { New-Object System.Windows.Forms.Button -Property @{ Text = $b; Width = 118; Height = 32; Top = 254 } }
for ($i = 0; $i -lt $buttons.Count; $i++) { $buttons[$i].Left = 12 + $i * 127 }
$log = New-Object System.Windows.Forms.TextBox -Property @{ Left = 12; Top = 296; Width = 760; Height = 254; Multiline = $true; ScrollBars = 'Vertical'; ReadOnly = $true; Font = New-Object System.Drawing.Font('Consolas', 8.5) }
$form.Controls.AddRange(@($info, $listLabel, $list, $add, $addPath, $forget, $sourcesButton, $ideLabel, $ideBox, $roleLabel, $roleBox) + $buttons + @($log))

$script:paths = @()
function Show-Repos {
    $keep = $list.SelectedIndex
    $script:paths = @(Get-Repos); $list.Items.Clear()
    foreach ($p in $script:paths) { [void]$list.Items.Add("$p   ($(Get-RepoStatus $p))") }
    if (-not $script:paths.Count) { [void]$list.Items.Add('(none yet - use "Add repository..." to choose a repository root)') }
    elseif ($keep -ge 0 -and $keep -lt $script:paths.Count) { $list.SelectedIndex = $keep } else { $list.SelectedIndex = 0 }
    $buttons[1].Enabled = [bool]@(Get-UpgradeTargets).Count
}
function Get-Selected {
    if ($list.SelectedIndex -lt 0 -or $list.SelectedIndex -ge $script:paths.Count) { [void][System.Windows.Forms.MessageBox]::Show('Add or select a repository first.', 'PBI Builder setup', 'OK', 'Information'); return $null }
    return $script:paths[$list.SelectedIndex]
}
function Write-Log([string]$text) { $log.Text = $text; $log.SelectionStart = $log.Text.Length; $log.ScrollToCaret() }
function Invoke-Busy([scriptblock]$work) { $form.Cursor = 'WaitCursor'; $log.Text = 'Working...'; $form.Refresh(); try { & $work } finally { $form.Cursor = 'Default'; Show-Repos } }
$askApply = { param($plan) [System.Windows.Forms.MessageBox]::Show("Planned changes:`n`n$((($plan -split "`r?`n") | Where-Object { $_ -match '^(create|update|retire|Review:)' } | Select-Object -First 25) -join "`n")`n`nApply them? Files that are replaced are backed up first.", 'Install / Upgrade', 'YesNo', 'Question') -eq 'Yes' }

function Add-Checked([string]$path) {
    # Pasted "Copy as path" quotes and trailing slashes are removed, as in the Akzo-Agent installer.
    $path = $path.Trim().Trim('"', "'").TrimEnd('\', '/')
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Container)) { [void][System.Windows.Forms.MessageBox]::Show("Folder not found (or not reachable): $path", 'Add repository', 'OK', 'Warning'); return }
    if (-not (Test-Path -LiteralPath (Join-Path $path '.git')) -and [System.Windows.Forms.MessageBox]::Show("$path has no .git folder. Use the repository root, not a parent folder or one project.`n`nAdd it anyway?", 'Add repository', 'YesNo', 'Warning') -ne 'Yes') { return }
    Add-Repo $path; Show-Repos; $list.SelectedIndex = [array]::IndexOf($script:paths, (Resolve-Path -LiteralPath $path).ProviderPath)
    Write-Log "Added $path ($(Get-RepoStatus $path)). Choose the editor and what the repository is, then click Install / Upgrade."
}
$add.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{ Description = 'Select the repository root (the folder that contains .git)'; ShowNewFolderButton = $false }
        if ($dlg.ShowDialog($form) -eq 'OK') { Add-Checked $dlg.SelectedPath }
    })
$addPath.Add_Click({
        Add-Type -AssemblyName Microsoft.VisualBasic
        $typed = [Microsoft.VisualBasic.Interaction]::InputBox('Type or paste (Ctrl+V) the full repository path, for example C:\src\MyRepo or \\server\share\MyRepo.', 'Add repository by path', '')
        if ($typed) { Add-Checked $typed }
    })
$forget.Add_Click({ $p = Get-Selected; if ($p) { Remove-Repo $p; Show-Repos; Write-Log "Removed $p from the list. Nothing in the repository was changed." } })
$buttons[0].Add_Click({
        $p = Get-Selected; if (-not $p) { return }
        Invoke-Busy { $r = Invoke-InstallFlow $p $(if ($ideBox.SelectedIndex -eq 1) { 'vscode' } else { 'visualstudio' }) $(@($Roles.Keys)[$roleBox.SelectedIndex]) $askApply; Write-Log ($r.text + "`r`n== $(if ($r.ok) { 'Finished' } else { 'Stopped: see above' }) ==") }
    })
$buttons[1].Add_Click({
        $targets = Get-UpgradeTargets
        if ([System.Windows.Forms.MessageBox]::Show("Upgrade $($targets.Count) repositories to $($PackageVersion)?`n`n$($targets -join "`n")`n`nEach one is previewed first; a repository with edited files is skipped and reported.", 'Upgrade all', 'YesNo', 'Question') -ne 'Yes') { return }
        Invoke-Busy { Write-Log (($targets | ForEach-Object { $r = Invoke-InstallFlow $_ 'visualstudio' 'legacy' { $true }; "== $_ : $(if ($r.ok) { 'upgraded' } else { 'NOT upgraded' })`r`n$($r.text)" }) -join "`r`n`r`n") }
    })
$buttons[2].Add_Click({ $p = Get-Selected; if ($p) { Invoke-Busy { $r = Invoke-Engine $p @('-Action', 'Repair'); Write-Log $r.text } } })
$buttons[3].Add_Click({ $p = Get-Selected; if ($p) { Invoke-Busy { $r = Invoke-Engine $p @('-Action', 'Verify'); Write-Log $r.text } } })
$buttons[4].Add_Click({
        $p = Get-Selected; if (-not $p) { return }
        if ([System.Windows.Forms.MessageBox]::Show("Remove the PBI Builder from`n$p ?`n`nKept: playbook\pbis (your PBIs and decisions), knowledge notes, backups and any file you edited.", 'Uninstall', 'YesNo', 'Question') -ne 'Yes') { return }
        Invoke-Busy { $r = Invoke-Engine $p @('-Action', 'Uninstall'); if ($r.code -eq 0) { Remove-Repo $p }; Write-Log $r.text }
    })
$buttons[5].Add_Click({ $form.Close() })

# Repository configuration for the selected installation: Legacy, CDMS, DAB and other reference repositories.
# Paths are stored relative to the repository when they share a drive; reference repositories are never written.
function ConvertTo-RepoRelative([string]$base, [string]$path) {
    try { $u = ([Uri]($base.TrimEnd('\') + '\')).MakeRelativeUri([Uri]$path); if (-not $u.IsAbsoluteUri) { return [Uri]::UnescapeDataString($u.ToString()).TrimEnd('/') } } catch { }
    return $path   # another drive or share: keep the absolute path
}
$sourcesButton.Add_Click({
        $p = Get-Selected; if (-not $p) { return }
        $cfgFile = Join-Path $p 'playbook\pbi-builder\config.json'
        if (-not (Test-Path -LiteralPath $cfgFile)) { [void][System.Windows.Forms.MessageBox]::Show('Install the PBI Builder in this repository first.', 'Repositories', 'OK', 'Information'); return }
        $cfg = [System.IO.File]::ReadAllText($cfgFile, $Utf8) | ConvertFrom-Json
        $d = New-Object System.Windows.Forms.Form -Property @{ Text = "Repositories for $(Split-Path -Leaf $p)"; Width = 700; Height = 454; FormBorderStyle = 'FixedDialog'; StartPosition = 'CenterParent'; MinimizeBox = $false; MaximizeBox = $false }
        $boxes = @{}; $y = 14
        foreach ($k in 'legacy', 'cdms', 'dab', 'ui') {
            $tb = New-Object System.Windows.Forms.TextBox -Property @{ Left = 200; Top = $y; Width = 370; Text = $(if ($cfg.sources.$k -eq '.') { '. (this repository)' } else { [string]$cfg.sources.$k }); Enabled = ($cfg.sources.$k -ne '.') }
            $bb = New-Object System.Windows.Forms.Button -Property @{ Left = 580; Top = $y - 2; Width = 90; Height = 26; Text = 'Browse...'; Enabled = $tb.Enabled; Tag = $tb }
            $bb.Add_Click({ param($s) $fb = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{ Description = 'Select the repository root'; ShowNewFolderButton = $false }; if ($fb.ShowDialog($d) -eq 'OK') { $s.Tag.Text = ConvertTo-RepoRelative $p $fb.SelectedPath } })
            $d.Controls.AddRange(@((New-Object System.Windows.Forms.Label -Property @{ Left = 12; Top = $y + 3; Width = 185; Text = $Roles[$k] }), $tb, $bb)); $boxes[$k] = $tb; $y += 34
        }
        $d.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Left = 12; Top = $y + 4; Width = 660; Text = 'Other reference repositories, one per line: Name = path (up to 10):' }))
        $others = New-Object System.Windows.Forms.TextBox -Property @{ Left = 12; Top = $y + 26; Width = 558; Height = 140; Multiline = $true; ScrollBars = 'Vertical'; Text = (@($cfg.others | Where-Object { $_ } | ForEach-Object { "$($_.name) = $($_.path)" }) -join "`r`n") }
        $addOther = New-Object System.Windows.Forms.Button -Property @{ Left = 580; Top = $y + 24; Width = 90; Height = 26; Text = 'Browse...' }
        $addOther.Add_Click({ $fb = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{ Description = 'Select another repository root'; ShowNewFolderButton = $false }; if ($fb.ShowDialog($d) -eq 'OK') { $others.AppendText($(if ($others.Text.Trim()) { "`r`n" } else { '' }) + "$(Split-Path -Leaf $fb.SelectedPath) = $(ConvertTo-RepoRelative $p $fb.SelectedPath)") } })
        $hint = New-Object System.Windows.Forms.Label -Property @{ Left = 12; Top = $y + 172; Width = 660; Height = 32; ForeColor = [System.Drawing.Color]::DimGray; Text = 'Each PBI picks its legacy repository and development target; the target decides which of these are implemented in and which are read-only references. Save previews the change and asks before writing.' }
        $save = New-Object System.Windows.Forms.Button -Property @{ Left = 480; Top = $y + 210; Width = 90; Height = 28; Text = 'Save' }
        $cancel = New-Object System.Windows.Forms.Button -Property @{ Left = 580; Top = $y + 210; Width = 90; Height = 28; Text = 'Cancel'; DialogResult = 'Cancel' }
        $save.Add_Click({
                # Configured is not verified: warn about invalid or missing folders, but allow saving (they may exist on another machine).
                $problems = @()
                $entries = @(foreach ($k in 'legacy', 'cdms', 'dab', 'ui') { if ($boxes[$k].Enabled) { [pscustomobject]@{ label = $Roles[$k]; path = $boxes[$k].Text.Trim().Trim('"') } } }) +
                @($others.Text -split "`r?`n" | Where-Object { $_.Trim() -and $_ -match '=' } | ForEach-Object { [pscustomobject]@{ label = ($_ -split '=', 2)[0].Trim(); path = ($_ -split '=', 2)[1].Trim().Trim('"') } })
                foreach ($e in $entries) {
                    if (-not $e.path) { continue }
                    if ($e.path -match '[<>"|?*]') { $problems += "$($e.label): the path has characters Windows does not allow ($($e.path))"; continue }
                    $full = if ([System.IO.Path]::IsPathRooted($e.path)) { $e.path } else { Join-Path $p ($e.path.Replace('/', '\')) }
                    if (-not (Test-Path -LiteralPath $full -PathType Container)) { $problems += "$($e.label): folder not found ($($e.path))" }
                }
                if ($problems.Count -and [System.Windows.Forms.MessageBox]::Show("Not verified:`n`n$($problems -join "`n")`n`nSave anyway? The paths stay configured, but the agent cannot read a folder that does not exist. Verify shows the result.", 'Repositories', 'YesNo', 'Warning') -ne 'Yes') { return }
                $d.DialogResult = 'OK'; $d.Close()
            })
        $d.Controls.AddRange(@($others, $addOther, $hint, $save, $cancel)); $d.CancelButton = $cancel
        if ($d.ShowDialog($form) -ne 'OK') { return }
        $extra = @()
        foreach ($k in 'legacy', 'cdms', 'dab', 'ui') { if ($boxes[$k].Enabled) { $v = $boxes[$k].Text.Trim().Trim('"'); $extra += @("-$((Get-Culture).TextInfo.ToTitleCase($k))Source", $(if ($v) { $v } else { ' ' })) } }
        $lines = @($others.Text -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { $_ -replace '^\s*([^=]+?)\s*=\s*', '$1=' })
        $extra += @('-OtherSource', $(if ($lines.Count) { $lines -join ';' } else { ';' }))
        Invoke-Busy { $r = Invoke-InstallFlow $p 'visualstudio' 'legacy' $askApply $extra; Write-Log ($r.text + "`r`n== $(if ($r.ok) { 'Repositories saved' } else { 'Stopped: see above' }) ==") }
    })
Show-Repos
[void]$form.ShowDialog()
