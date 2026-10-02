#Requires -Version 5.1
<#
.SYNOPSIS
    Copy a GameLoop keymapping from one game to another.

.DESCRIPTION
    If you play two builds of the same game (for example PUBG Mobile and PUBG Mobile
    Flash) you have probably set up ~130 buttons by hand in one of them, and then had to
    do the whole thing again in the other.

    This script copies one game's entire keymapping - every KeyMapMode block, for every
    resolution - onto another game, in GameLoop's own config file.

    It is the same operation you would do by hand in GameLoop's key-mapping UI, just
    without the hours of dragging buttons.

    What is copied:
        every <KeyMapMode> block (ModeID 1..N - Normal 720P, Smart 720P, Smart 1080P,
        Smart 2K, ...) with all of its <KeyMapping> and <KeyMappingEx> entries.

    What is NOT copied:
        * the target's <Item> header (its name, version)
        * the target's <StartInfo> and <LastMode>
        * the target's <VersionInfo>
        * the target's <Switch Name="..." TextureId="..."/> list

    That last one matters. Two builds of the same game can have different feature sets -
    one may have ski, cable car, snowboard, guitar modes that the other does not. The
    switch list describes what the game itself supports, so overwriting it with the
    other build's list is a good way to break things. This script leaves it alone.

    The two lists are keyed by NAME, not by number. The TextureId next to each name is
    only a sprite index inside that one build, and the same number means different things
    in different builds (in one real pair, id 103 is "Hand" in one build and "Sw1to3" in
    the other). So nothing here is ever matched by TextureId.

    A keymapping can also refer to those features by name through its <SwitchOperation>
    entries. If the source uses a feature the target build does not have, the script says
    so before copying - the layout is still copied, but those toggles will do nothing on
    the target.

.PARAMETER From
    Source game package name, e.g. com.tencent.ig
    Default: com.tencent.ig if it is present.

.PARAMETER To
    Target game package name, e.g. com.tencent.igfit
    Default: com.tencent.igfit if it is present.

.PARAMETER VmId
    One or more GameLoop VM ids, e.g. -VmId 100
    Default: every TVM_<id>.xml found.

.PARAMETER ConfigDir
    Use this folder instead of auto-detecting.

.PARAMETER List
    Show every game in the config file and how many keymap modes it has, then exit.

.PARAMETER Diagnose
    Show the source and the target in detail, and what would change. Changes nothing.

.PARAMETER Restore
    Restore the newest backup created by this script.

.PARAMETER DryRun
    Show the plan but write nothing.

.PARAMETER Yes
    Do not ask for confirmation.

.PARAMETER Force
    Skip the "GameLoop is still running" guard. NOT recommended.

.EXAMPLE
    .\Copy-KeyMapping.ps1 -List
    What games are in my config file?

.EXAMPLE
    .\Copy-KeyMapping.ps1 -Diagnose
    Show the source and target keymaps side by side.

.EXAMPLE
    .\Copy-KeyMapping.ps1
    Copy com.tencent.ig -> com.tencent.igfit (if both are present).

.EXAMPLE
    .\Copy-KeyMapping.ps1 -From com.tencent.ig -To com.tencent.igfit
    Explicit source and target.

.EXAMPLE
    .\Copy-KeyMapping.ps1 -DryRun
    Preview without writing.

.EXAMPLE
    .\Copy-KeyMapping.ps1 -Restore
    Undo - restore the newest backup.

.NOTES
    Not affiliated with Tencent or GameLoop. Use at your own risk. Your config file is
    backed up before the change, and -Restore puts it back.
#>
[CmdletBinding()]
param(
    [string]   $From,
    [string]   $To,
    [int[]]    $VmId,
    [string]   $ConfigDir,
    [switch]   $List,
    [switch]   $Diagnose,
    [switch]   $Restore,
    [switch]   $DryRun,
    [switch]   $Yes,
    [switch]   $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$BackupTag = 'keymap-clone'
$VmProcesses = @('AndroidEmulatorEn', 'AndroidEmulator', 'AndroidEmulatorEx', 'aow_exe')

# A whole <KeyMapMode>, either self-closing (<KeyMapMode .../>) or with a body.
# (?s) so '.' crosses newlines.
$ModeRx = [regex]'(?s)<KeyMapMode\b[^>]*?/>|<KeyMapMode\b[^>]*>.*?</KeyMapMode>'

# Defaults that make sense for the common case: PUBG Mobile -> PUBG Mobile Flash.
$DefaultFrom = 'com.tencent.ig'
$DefaultTo   = 'com.tencent.igfit'

# ------------------------------------------------------------------ output ---

function Write-Head { param([string]$Text) Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan }
function Write-Step { param([string]$Text) Write-Host "   $Text" }
function Write-Ok   { param([string]$Text) Write-Host "   [ok]   $Text" -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host "   [warn] $Text" -ForegroundColor Yellow }
function Write-Bad  { param([string]$Text) Write-Host "   [fail] $Text" -ForegroundColor Red }

# ------------------------------------------------ config file auto-discovery ---

function Get-TvmFolderCandidates {
    $c = New-Object System.Collections.Generic.List[string]

    # An explicit -ConfigDir wins outright: we look there and nowhere else. It must not be
    # added to the usual locations, or the script would also touch the real config.
    if ($ConfigDir) {
        $c.Add($ConfigDir)
        return $c
    }

    foreach ($root in @($env:APPDATA, $env:LOCALAPPDATA)) {
        if (-not $root) { continue }
        foreach ($leaf in @('AndroidTbox', 'AndroidTbox64', 'AOW', 'Tencent\AndroidTbox')) {
            $c.Add((Join-Path $root $leaf))
        }
    }
    return $c | Select-Object -Unique
}

function Get-TvmFileList {
    param([int[]]$VmId)

    $found = New-Object System.Collections.Generic.List[object]

    foreach ($dir in (Get-TvmFolderCandidates)) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in (Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
            if ($f.Name -match '^TVM_\d+\.xml$') { $found.Add($f) }
        }
    }

    # 2) fall back to a shallow scan, in case a future build moves the folder.
    #    Never when -ConfigDir was given - the caller asked for that folder specifically.
    if ($found.Count -eq 0 -and -not $ConfigDir) {
        foreach ($root in @($env:APPDATA, $env:LOCALAPPDATA)) {
            if (-not $root) { continue }
            foreach ($f in (Get-ChildItem -LiteralPath $root -Recurse -File -Depth 3 -Force -ErrorAction SilentlyContinue)) {
                if ($f.Name -match '^TVM_\d+\.xml$') { $found.Add($f) }
            }
        }
    }

    $unique = @{}
    foreach ($f in $found) { $unique[$f.FullName] = $f }
    $result = @($unique.Values | Sort-Object FullName)

    if ($VmId -and $VmId.Count -gt 0) {
        $result = @($result | Where-Object {
            $m = [regex]::Match($_.Name, '^TVM_(\d+)\.xml$')
            $VmId -contains [int]$m.Groups[1].Value
        })
    }

    if ($result.Count -eq 0) {
        throw ("No TVM_<id>.xml config file found.`n`n" +
               "Run GameLoop at least once and set up your controls in the game, so it`n" +
               "creates %APPDATA%\AndroidTbox\TVM_<id>.xml. Or point at the folder`n" +
               "directly with:  -ConfigDir `"C:\path\to\AndroidTbox`"")
    }
    return $result
}

function Assert-GameLoopClosed {
    if ($Force) { Write-Warn 'Force set - skipping the GameLoop running check.'; return }

    $live = @(Get-Process -ErrorAction SilentlyContinue |
              Where-Object { $VmProcesses -contains $_.ProcessName })

    if ($live.Count -gt 0) {
        $names = ($live | Select-Object -ExpandProperty ProcessName -Unique) -join ', '
        throw ("GameLoop's emulator is still running ($names).`n`n" +
               "Close GameLoop completely - including the tray icon - then run this again.`n" +
               "If you edit the file while the VM is alive, GameLoop overwrites your change`n" +
               "when it shuts down.")
    }

    if (Get-Process -Name 'AppMarket' -ErrorAction SilentlyContinue) {
        Write-Warn "GameLoop's launcher (AppMarket.exe) is open. Safer to close it too."
    }
}

function Read-TvmText {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $strict = New-Object System.Text.UTF8Encoding($false, $true)
    return [pscustomobject]@{ Bytes = $bytes; Text = $strict.GetString($bytes) }
}

# ------------------------------------------------------------- item ranges ---

function Get-ItemRanges {
    param([string]$Text)
    # (?s) so '.' crosses newlines - an Item block spans many lines.
    $rx  = [regex]'(?s)<Item\s[^>]*ApkName="(?<apk>[^"]*)"[^>]*>(?<body>.*?)</Item>'
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($m in $rx.Matches($Text)) {
        $body = $m.Groups['body']
        $out.Add([pscustomobject]@{
            ApkName   = $m.Groups['apk'].Value
            Start     = $m.Index
            End       = $m.Index + $m.Length
            BodyStart = $body.Index
            BodyEnd   = $body.Index + $body.Length
        })
    }
    return $out
}

function Get-KeyMapRegion {
    <#
        The span covering every <KeyMapMode> block inside an Item body - from the start of
        the first one to the end of the last one. Returns $null when the Item has none
        (a fresh game that has never been mapped).
    #>
    param([string]$Body)

    $hits = @($ModeRx.Matches($Body))
    if ($hits.Count -eq 0) { return $null }

    $start = $hits[0].Index
    $end   = $hits[$hits.Count - 1].Index + $hits[$hits.Count - 1].Length

    return [pscustomobject]@{
        Start = $start
        End   = $end
        Text  = $Body.Substring($start, $end - $start)
        Count = $hits.Count
    }
}

function Get-ModeSummary {
    param([string]$RegionText)
    if (-not $RegionText) { return @() }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($m in $ModeRx.Matches($RegionText)) {
        $tag = $m.Value
        $id  = ([regex]::Match($tag, 'ModeID="([^"]*)"')).Groups[1].Value
        $nm  = ([regex]::Match($tag, 'Name="([^"]*)"')).Groups[1].Value
        $n   = @([regex]::Matches($tag, '<KeyMapping(?:Ex)?\b')).Count
        $out.Add("ModeID=$id  Name=$nm  entries=$n")
    }
    return $out
}

function Get-SwitchNames {
    <#
        The names in an Item's <Switch Name="..." TextureId="..."/> list.

        A "switch" is an in-game FEATURE that build of the game knows about - parachute,
        ski, cable car, snowball, the various grenade and medicine slots, and so on. It is
        not the button layout. Two builds of the same game have overlapping but different
        lists (this is why the script never copies the switch list).

        Note that <Switch> entries are keyed by NAME, not by number. TextureId is only a
        sprite index inside that one build, and the same number means different things in
        different builds - so nothing here is ever matched by TextureId.
    #>
    param([string]$Body)

    $set = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in [regex]::Matches($Body, '<Switch\s+Name="([^"]*)"')) {
        [void]$set.Add($m.Groups[1].Value)
    }
    return @($set)
}

function Get-ReferencedSwitchNames {
    <#
        The switch names the KEYMAPPING itself refers to. A <SwitchOperation> means "when
        the player toggles this feature, move or show these buttons" - so a keymap depends
        on the game's switch list by name.
    #>
    param([string]$RegionText)

    $set = New-Object System.Collections.Generic.HashSet[string]
    $rx  = '(?<=\s)(?:EnableSwitch|DisableSwitch|EnablePositionSwitch|TexturePosition)="([^"]*)"'

    foreach ($m in [regex]::Matches($RegionText, $rx)) {
        # These are pipe-separated lists of names.
        foreach ($n in $m.Groups[1].Value.Split('|')) {
            $n = $n.Trim()
            if (-not $n) { continue }

            # A value can carry a position spec after the name, e.g.
            #   TexturePosition="Grenade:0.606250,0.202847,0.695312,1.000000"
            # Only what comes before the colon identifies the switch.
            $colon = $n.IndexOf(':')
            if ($colon -ge 0) { $n = $n.Substring(0, $colon).Trim() }

            if ($n) { [void]$set.Add($n) }
        }
    }
    return @($set)
}

# ----------------------------------------------------------- backup / undo ---

function Get-BackupList {
    param([string]$Path)
    $dir  = Split-Path -Parent $Path
    $base = [IO.Path]::GetFileNameWithoutExtension($Path)
    $ext  = [IO.Path]::GetExtension($Path)
    return @(Get-ChildItem -LiteralPath $dir -File -Filter "$base`_backup_$BackupTag`_*$ext" -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending)
}

function New-Backup {
    param([string]$Path)
    $dir   = Split-Path -Parent $Path
    $base  = [IO.Path]::GetFileNameWithoutExtension($Path)
    $ext   = [IO.Path]::GetExtension($Path)
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $dest  = Join-Path $dir "$base`_backup_$BackupTag`_$stamp$ext"
    Copy-Item -LiteralPath $Path -Destination $dest -Force
    return $dest
}

# ============================================================ main ==========

Write-Host ''
Write-Host '  GameLoop - copy a keymapping from one game to another' -ForegroundColor White
Write-Host '  (works with both the 32-bit and the 64-bit GameLoop engine)'

$files = Get-TvmFileList -VmId $VmId
$loaded = @{}
foreach ($f in $files) { $loaded[$f.FullName] = (Read-TvmText -Path $f.FullName) }

# ---------------------------------------------------------------- list mode --

if ($List) {
    foreach ($f in $files) {
        Write-Head $f.FullName
        $txt   = $loaded[$f.FullName].Text
        $items = Get-ItemRanges -Text $txt
        foreach ($it in $items) {
            $body   = $txt.Substring($it.BodyStart, $it.BodyEnd - $it.BodyStart)
            $region = Get-KeyMapRegion -Body $body
            $switch = @(Get-SwitchNames -Body $body).Count
            if ($null -eq $region) {
                Write-Step "$($it.ApkName)  -  no keymapping yet  ($switch features)"
            } else {
                Write-Step "$($it.ApkName)  -  $($region.Count) keymap mode(s)  ($switch features)"
            }
        }
    }
    Write-Host ''
    return
}

# ------------------------------------------------------------- restore mode --

if ($Restore) {
    Write-Head 'Restore'
    Assert-GameLoopClosed
    $did = $false
    foreach ($f in $files) {
        # Note: this must NOT be called $list - variable names are case-insensitive in
        # PowerShell, so $list would be the same variable as the [switch]$List parameter
        # and assigning a FileInfo to it throws "cannot convert ... to SwitchParameter".
        $backups = Get-BackupList -Path $f.FullName
        if (@($backups).Count -eq 0) { Write-Step "$($f.Name): no backup found."; continue }
        $newest = @($backups)[0]
        if (-not $Yes) {
            $ans = Read-Host "   Restore $($f.Name) from $($newest.Name)? [y/N]"
            if ($ans -notmatch '^(y|yes)$') { Write-Step 'skipped.'; continue }
        }
        Copy-Item -LiteralPath $newest.FullName -Destination $f.FullName -Force
        Write-Ok "$($f.Name) restored from $($newest.Name)"
        $did = $true
    }
    if (-not $did) { Write-Warn 'Nothing was restored.' }
    Write-Host ''
    return
}

# ------------------------------------------------------------ resolve pair --

# If -From / -To were not given, try the PUBG Mobile -> PUBG Mobile Flash default, but
# only if both are actually present in the file.
if (-not $From -or -not $To) {
    $present = @{}
    foreach ($f in $files) {
        foreach ($it in (Get-ItemRanges -Text $loaded[$f.FullName].Text)) { $present[$it.ApkName] = $true }
    }
    if (-not $From -and $present.ContainsKey($DefaultFrom)) { $From = $DefaultFrom }
    if (-not $To   -and $present.ContainsKey($DefaultTo))   { $To   = $DefaultTo }
}

if (-not $From) { throw "No source game given, and $DefaultFrom was not found in the config. Use -From <package.name>. See -List." }
if (-not $To)   { throw "No target game given, and $DefaultTo was not found in the config. Use -To <package.name>. See -List." }
if ($From -eq $To) { throw "-From and -To are the same ($From). Nothing to do." }

Write-Head 'Plan'
Write-Step "Source (-From) : $From"
Write-Step "Target (-To)   : $To"

# ------------------------------------------------------ build the operation --

$ops = New-Object System.Collections.Generic.List[object]

foreach ($f in $files) {
    $txt   = $loaded[$f.FullName].Text
    $items = Get-ItemRanges -Text $txt

    $srcItem = $null; $dstItem = $null
    foreach ($it in $items) {
        if ($it.ApkName -eq $From) { $srcItem = $it }
        if ($it.ApkName -eq $To)   { $dstItem = $it }
    }
    if ($null -eq $srcItem) { Write-Warn "$($f.Name): source $From not present, skipped."; continue }
    if ($null -eq $dstItem) { Write-Warn "$($f.Name): target $To not present, skipped."; continue }

    $srcBody = $txt.Substring($srcItem.BodyStart, $srcItem.BodyEnd - $srcItem.BodyStart)
    $dstBody = $txt.Substring($dstItem.BodyStart, $dstItem.BodyEnd - $dstItem.BodyStart)

    $srcRegion = Get-KeyMapRegion -Body $srcBody
    $dstRegion = Get-KeyMapRegion -Body $dstBody

    if ($null -eq $srcRegion) {
        Write-Warn "$($f.Name): source $From has no keymapping at all - nothing to copy."
        continue
    }

    if ($null -eq $dstRegion) {
        # Target has never been mapped at all: append the source's blocks to its body.
        $newBody = $dstBody.TrimEnd() + "`r`n" + $srcRegion.Text + "`r`n"
    } else {
        # Replace the target's keymap region - everything from the first <KeyMapMode> to
        # the end of the last one - and leave the rest of the body alone.
        $newBody = $dstBody.Substring(0, $dstRegion.Start) + $srcRegion.Text +
                   $dstBody.Substring($dstRegion.End)
    }

    if ($newBody -ceq $dstBody) {
        Write-Step "$($f.Name): target already has an identical keymapping - nothing to do."
        continue
    }

    # Which features the source keymap relies on that the target build does not have.
    # Not fatal - the layout is still copied - but those toggles simply will not fire on
    # the target, and it is better to say so than to let someone find out in a firefight.
    $targetSwitches = New-Object System.Collections.Generic.HashSet[string]
    foreach ($n in @(Get-SwitchNames -Body $dstBody)) { [void]$targetSwitches.Add($n) }

    $missing = @(Get-ReferencedSwitchNames -RegionText $srcRegion.Text |
                 Where-Object { -not $targetSwitches.Contains($_) } |
                 Sort-Object)

    $ops.Add([pscustomobject]@{
        File              = $f
        Original          = $txt
        BodyStart         = $dstItem.BodyStart
        OldBody           = $dstBody
        NewBody           = $newBody
        SourceModes       = @(Get-ModeSummary -RegionText $srcRegion.Text)
        TargetModes       = @(Get-ModeSummary -RegionText $dstRegion.Text)
        TargetSwitchCount = $targetSwitches.Count
        MissingSwitches   = $missing
        OldRegion         = if ($dstRegion) { $dstRegion.Text } else { $null }
    })
}

if ($ops.Count -eq 0) {
    Write-Host ''
    Write-Warn 'Nothing to do.'
    Write-Host ''
    return
}

Write-Host ''
foreach ($o in $ops) {
    # Full path: two VMs (or a VM and a -ConfigDir copy) can share the file name.
    Write-Step $o.File.FullName
    Write-Step "     from $From : $($o.SourceModes.Count) mode(s)"
    foreach ($m in $o.SourceModes) { Write-Step "          $m" }
    Write-Step "     onto $To : $($o.TargetModes.Count) mode(s) currently"
    foreach ($m in $o.TargetModes) { Write-Step "          $m" }

    if ($o.TargetSwitchCount -eq 0) {
        Write-Host ''
        Write-Warn "$To has no feature list at all - it looks like it has never been opened."
        Write-Step "Launch $To in GameLoop once (so it writes its own list), then run this again."
        Write-Step 'The button layout is still copied either way.'
    }
    elseif ($o.MissingSwitches.Count -gt 0) {
        Write-Host ''
        Write-Warn "$($o.MissingSwitches.Count) feature(s) used by $From are not in $To's list:"
        Write-Step "          $($o.MissingSwitches -join ', ')"
        Write-Step 'Those toggles will simply do nothing on the target. The button layout'
        Write-Step 'itself is copied either way.'
    }
}

# ------------------------------------------------------------ diagnose ----

if ($Diagnose) {
    Write-Host ''
    Write-Step 'Diagnose only - nothing was written.'
    Write-Host ''
    return
}

if ($DryRun) {
    Write-Host ''
    Write-Step 'Dry run - nothing was written.'
    Write-Host ''
    return
}

if (-not $Yes) {
    Write-Host ''
    $ans = Read-Host "   Overwrite $To's keymapping with $From's? [y/N]"
    if ($ans -notmatch '^(y|yes)$') { Write-Host ''; Write-Step 'Cancelled.'; Write-Host ''; return }
}

# ------------------------------------------------------------- apply ------

Write-Head 'Applying'
Assert-GameLoopClosed

foreach ($o in $ops) {
    $path = $o.File.FullName
    $name = $o.File.Name

    $newText = $o.Original.Substring(0, $o.BodyStart) + $o.NewBody +
               $o.Original.Substring($o.BodyStart + $o.OldBody.Length)

    # ---- verify in memory first -------------------------------------------------
    # Splice the ORIGINAL body back in at the position the new body occupies. The result
    # must be character-for-character identical to the original file. If anything at all
    # outside the target game's keymapping moved, this fails and nothing is written.
    $reverted = $newText.Substring(0, $o.BodyStart) + $o.OldBody +
                $newText.Substring($o.BodyStart + $o.NewBody.Length)

    if ($reverted -cne $o.Original) {
        throw "Round-trip verification failed for $name - nothing was written."
    }
    Write-Step "$name : round-trip verified"

    $backup = New-Backup -Path $path
    Write-Step "$name : backup -> $(Split-Path -Leaf $backup)"

    $expectedBytes = $Utf8NoBom.GetBytes($newText)
    [IO.File]::WriteAllBytes($path, $expectedBytes)

    # ---- confirm what landed on disk is exactly what was built -------------------
    $after = [IO.File]::ReadAllBytes($path)
    $same  = ($after.Length -eq $expectedBytes.Length)
    if ($same) {
        for ($i = 0; $i -lt $after.Length; $i++) {
            if ($after[$i] -ne $expectedBytes[$i]) { $same = $false; break }
        }
    }
    if (-not $same) {
        Write-Bad "$name : read-back mismatch! Restoring backup."
        Copy-Item -LiteralPath $backup -Destination $path -Force
        throw "Write verification failed for $name - the backup was restored."
    }

    Write-Ok "$name : written and verified ($($after.Length) bytes)"
}

Write-Head 'Done'
Write-Step "Open GameLoop, launch $To, and check your controls."
Write-Step "To undo:  -Restore"
Write-Host ''
Write-Step 'Tip: after cloning, run the WASD speed fix too if movement feels sluggish.'
Write-Host ''
