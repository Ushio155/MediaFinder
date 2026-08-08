function Get-ScriptDir {
    if ($PSScriptRoot) { return $PSScriptRoot }
    return (Split-Path -Parent $MyInvocation.MyCommand.Path)
}

function Get-Config {
    param([string]$ConfigPath = $null)
    if (-not $ConfigPath) { $ConfigPath = Join-Path (Get-ScriptDir) 'MediaFinder.config.json' }
    $script:CfgPath = $ConfigPath
    if (Test-Path -LiteralPath $ConfigPath) {
        $c = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $c.ignoredPrivacyDirs) { $c | Add-Member -NotePropertyName ignoredPrivacyDirs -NotePropertyValue @() -Force }
        if ($null -eq $c.logEnabled) { $c | Add-Member -NotePropertyName logEnabled -NotePropertyValue $true -Force }
        if ($null -eq $c.logIntervalSeconds) { $c | Add-Member -NotePropertyName logIntervalSeconds -NotePropertyValue 30 -Force }
        if ($null -eq $c.logKeepDays) { $c | Add-Member -NotePropertyName logKeepDays -NotePropertyValue 30 -Force }
        return $c
    }
    $u = $env:USERPROFILE
    $defaults = [ordered]@{
        autoDetect = $true
        autoRefresh = $true
        refreshInterval = 5
        watchPaths = @(
            '%USERPROFILE%\Videos',
            '%USERPROFILE%\Downloads',
            '%USERPROFILE%\Pictures',
            '%USERPROFILE%\Documents\OBS Studio',
            '%USERPROFILE%\Music'
        )
        extensions = [ordered]@{
            video = @('.mp4','.mkv','.mov','.avi','.ts','.flv','.webm','.m4v','.m2ts','.wmv','.mpg','.mpeg')
            image = @('.png','.jpg','.jpeg','.bmp','.webp','.gif','.tiff','.heic','.jfif')
            audio = @('.mp3','.flac','.wav','.m4a','.aac','.ogg','.opus','.wma')
        }
        indexProvider = 'auto'
        everythingDllPath = ''
        autoStartEverything = $true
        autostartEverythingOnBoot = $true
        stopEverythingOnExit = $false
        ignoredPrivacyDirs = @()
        logEnabled = $true
        logIntervalSeconds = 30
        logKeepDays = 30
        indexFile = (Join-Path (Get-ScriptDir) 'MediaFinder.index.json')
    }
    $defaults | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
    Write-Host "已创建配置文件: $ConfigPath (可用记事本编辑 watchPaths; 开启 autoDetect 会自动识别常见目录)"
    return $defaults
}

function Build-ExtMap($cfg) {
    $map = @{}
    foreach ($k in 'video','image','audio') {
        foreach ($e in $cfg.extensions.$k) { $map[$e.ToLower()] = $k }
    }
    return $map
}

function Get-IndexFile($cfg) {
    if ($cfg.indexFile) {
        $dir = Split-Path -Parent $cfg.indexFile
        if ($dir -and (Test-Path -LiteralPath $dir)) { return $cfg.indexFile }
    }
    return (Join-Path (Get-ScriptDir) 'MediaFinder.index.json')
}

function Load-Index($path) {
    $list = New-Object System.Collections.ArrayList
    if (Test-Path -LiteralPath $path) {
        $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($j) { foreach ($x in $j) { $list.Add($x) | Out-Null } }
    }
    return $list
}

function Save-Index($path, $list) {
    $tmp = "$path.tmp"
    if ($null -ne $list -and $list.Count -gt 0) {
        $list | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $tmp -Encoding UTF8
    }
    else {
        Set-Content -LiteralPath $tmp -Value "[]" -Encoding UTF8
    }
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

function Resolve-WatchConfig($cfg) {
    $entries = New-Object System.Collections.ArrayList
    $seen = @{}
    function Add-Entry($path, $include, $exclude) {
        $rp = [Environment]::ExpandEnvironmentVariables([string]$path)
        if (-not $rp) { return }
        $k = $rp.ToLowerInvariant().TrimEnd('\')
        if ($seen.ContainsKey($k)) { return }
        $seen[$k] = $true
        $entries.Add([pscustomobject]@{
            Path = $rp
            Include = @($include)
            Exclude = @($exclude)
        }) | Out-Null
    }
    foreach ($p in $cfg.watchPaths) {
        $inc = @(); $exc = @()
        if ($cfg.includeFilters) {
            $prop = $cfg.includeFilters.PSObject.Properties["$p"]
            if ($prop) { $inc = @($prop.Value) }
        }
        if ($cfg.excludeFilters) {
            $prop = $cfg.excludeFilters.PSObject.Properties["$p"]
            if ($prop) { $exc = @($prop.Value) }
        }
        Add-Entry $p $inc $exc
    }
    if ($cfg.autoDetect -ne $false) {
        $u = $env:USERPROFILE
        foreach ($sub in 'Videos','Downloads','Pictures','Music') {
            $ap = Join-Path $u $sub
            if (Test-Path -LiteralPath $ap) { Add-Entry $ap @() @() }
        }
        $drives = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root.TrimEnd('\') } | Where-Object { $_ })
        foreach ($d in $drives) {
            foreach ($g in @('WeGameApps','obs-studio')) {
                $gp = Join-Path $d $g
                if (Test-Path -LiteralPath $gp) {
                    if ($g -eq 'WeGameApps') { Add-Entry $gp @('screenshot','截图') @() }
                    elseif ($g -eq 'obs-studio') { Add-Entry $gp @() @('\data\','\bin\','\obs-plugins\') }
                }
            }
            foreach ($s in 'Videos','Music') {
                $dp = Join-Path $d $s
                if (Test-Path -LiteralPath $dp) { Add-Entry $dp @() @() }
            }
        }
        $jyDraft = Join-Path $env:LOCALAPPDATA 'JianyingPro\User Data\Projects\com.lveditor.draft'
        if (Test-Path -LiteralPath $jyDraft) { Add-Entry $jyDraft @() @() }
    }
    return $entries
}

function Find-PrivacyDirs($cfg) {
    $docs = Join-Path $env:USERPROFILE 'Documents'
    $cands = @(
        @{ Kind = '微信'; Path = (Join-Path $docs 'WeChat Files');   Hint = '微信聊天中接收的文件' },
        @{ Kind = '微信'; Path = (Join-Path $docs 'xwechat_files');  Hint = '微信(新版)聊天中接收的文件' },
        @{ Kind = 'QQ';   Path = (Join-Path $docs 'Tencent Files');  Hint = 'QQ/TIM 聊天中接收的文件' }
    )
    $ignored = @(@($cfg.ignoredPrivacyDirs) | Where-Object { $_ })
    $current = @((Resolve-WatchConfig $cfg) | ForEach-Object { $_.Path })
    $res = New-Object System.Collections.ArrayList
    foreach ($c in $cands) {
        $rp = [Environment]::ExpandEnvironmentVariables([string]$c.Path)
        if (-not $rp -or -not (Test-Path -LiteralPath $rp)) { continue }
        if ($ignored -contains $rp) { continue }
        if ($current -contains $rp) { continue }
        $res.Add([pscustomobject]@{ kind = $c.Kind; path = $rp; hint = $c.Hint; excludes = @(Get-PrivacyExcludes $c.Kind) }) | Out-Null
    }
    return @($res)
}

function Get-PrivacyExcludes($kind) {
    switch ([string]$kind) {
        'QQ' {
            return @(
                '\Image\', '\Video\', '\thumb\', '\FileCache\',
                '\nt_data\Pic\', '\nt_data\avatar\', '\nt_data\Emoji\', '\nt_data\Ptt\',
                '\nt_data\msf\', '\nt_data\mmkv\', '\nt_data\flashfransfer\', '\nt_data\ams\',
                '\nt_data\dataline\', '\nt_data\log', '\nt_data\OnlineStatus\', '\nt_data\UnitedConfig\',
                '\nt_data\VasUpdateSystem\', '\nt_data\PokeFace\', '\nt_data\WeatherBgCache\',
                '\nt_db\', '\nt_temp\', '\Thumb\', '\ThumbTemp\'
            )
        }
        '微信' {
            return @(
                '\cache\', '\WeAppIcon\', '\avatar\',
                '\msg\image\', '\msg\video\', '\msg\voice\', '\msg\attach\', '\msg\emoji\', '\msg\applet\', '\msg\backup\',
                '\FileStorage\Cache\', '\FileStorage\Image\', '\FileStorage\Video\', '\FileStorage\MsgAttach\'
            )
        }
        default { return @() }
    }
}

# ---------- 活动日志 ----------

function Get-LogDir($cfg) {
    $d = Join-Path (Get-ScriptDir) 'logs'
    try { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } } catch {}
    return $d
}

function Get-LogSnapshotPath($cfg) { Join-Path (Get-LogDir $cfg) 'snapshot.json' }

function Get-MediaSnapshot($cfg, $extMap, $useEverything) {
    $list = New-Object System.Collections.ArrayList
    if ($useEverything) {
        $entries = Resolve-WatchConfig $cfg
        foreach ($r in @(Search-Everything $cfg $extMap $entries $null $null $null 50000)) {
            if (-not $r -or -not $r.FullPath) { continue }
            [void]$list.Add([pscustomobject]@{
                Name = $r.Name
                FullPath = $r.FullPath
                Size = if ($null -ne $r.Size) { [int64]$r.Size } else { 0 }
                LastWriteTime = if ($null -ne $r.LastWriteTime) { $r.LastWriteTime } else { [DateTime]::MinValue }
            })
        }
    }
    else {
        foreach ($x in @(Load-Index (Get-IndexFile $cfg))) {
            if (-not $x -or -not $x.FullPath) { continue }
            [void]$list.Add([pscustomobject]@{
                Name = $x.Name
                FullPath = $x.FullPath
                Size = if ($null -ne $x.Size) { [int64]$x.Size } else { 0 }
                LastWriteTime = if ($null -ne $x.LastWriteTime) { [DateTime]$x.LastWriteTime } else { [DateTime]::MinValue }
            })
        }
    }
    return @($list)
}

function Compare-MediaSnapshots($prev, $curr) {
    $events = New-Object System.Collections.ArrayList
    $pMap = @{}
    $cMap = @{}
    $cByName = @{}
    foreach ($p in @($prev)) {
        if ($p.FullPath) { $pMap[$p.FullPath.ToLowerInvariant()] = $p }
    }
    foreach ($c in @($curr)) {
        if (-not $c.FullPath) { continue }
        $cMap[$c.FullPath.ToLowerInvariant()] = $c
        $n = $c.Name.ToLowerInvariant()
        if (-not $cByName.ContainsKey($n)) { $cByName[$n] = New-Object System.Collections.ArrayList }
        [void]$cByName[$n].Add($c)
    }
    $added = @()
    foreach ($c in @($curr)) {
        if ($c.FullPath -and -not $pMap.ContainsKey($c.FullPath.ToLowerInvariant())) { $added += $c }
    }
    $gone = @()
    foreach ($p in @($prev)) {
        if ($p.FullPath -and -not $cMap.ContainsKey($p.FullPath.ToLowerInvariant())) { $gone += $p }
    }
    $usedAdd = @{}
    $movedOld = @{}
    foreach ($g in $gone) {
        $n = $g.Name.ToLowerInvariant()
        if (-not $cByName.ContainsKey($n)) { continue }
        $best = $null
        foreach ($cand in $cByName[$n]) {
            $k = $cand.FullPath.ToLowerInvariant()
            if ($usedAdd.ContainsKey($k)) { continue }
            $sameSize = ($null -ne $g.Size -and $null -ne $cand.Size -and $g.Size -eq $cand.Size -and $g.Size -gt 0)
            $sameTime = ($null -ne $g.LastWriteTime -and $null -ne $cand.LastWriteTime -and $g.LastWriteTime -gt [DateTime]::MinValue -and $cand.LastWriteTime -gt [DateTime]::MinValue -and [Math]::Abs(($g.LastWriteTime - $cand.LastWriteTime).TotalSeconds) -le 2)
            if ($sameSize) { $best = $cand; break }
            if ($sameTime) { $best = $cand; break }
            if (-not $best) { $best = $cand }
        }
        if ($best) {
            $usedAdd[$best.FullPath.ToLowerInvariant()] = $true
            $movedOld[$g.FullPath.ToLowerInvariant()] = $true
            [void]$events.Add([pscustomobject]@{ Type = 'moved'; Name = $g.Name; Old = $g.FullPath; New = $best.FullPath })
        }
    }
    foreach ($a in $added) {
        if (-not $usedAdd.ContainsKey($a.FullPath.ToLowerInvariant())) {
            [void]$events.Add([pscustomobject]@{ Type = 'added'; Name = $a.Name; Old = $null; New = $a.FullPath })
        }
    }
    foreach ($g in $gone) {
        if (-not $movedOld.ContainsKey($g.FullPath.ToLowerInvariant())) {
            [void]$events.Add([pscustomobject]@{ Type = 'gone'; Name = $g.Name; Old = $g.FullPath; New = $null })
        }
    }
    return @($events)
}

function Get-EventFolder($old, $new) {
    $p = if ($new) { $new } else { $old }
    if (-not $p) { return '' }
    $parent = Split-Path -Parent $p
    if (-not $parent) { return '' }
    return (Split-Path -Leaf $parent)
}

function Write-MediaLog($cfg, $event) {
    if (-not $event) { return }
    $d = Get-LogDir $cfg
    $time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = [pscustomobject]@{
        t = $time
        type = [string]$event.Type
        name = [string]$event.Name
        folder = [string](Get-EventFolder $event.Old $event.New)
        old = [string]$event.Old
        new = [string]$event.New
    } | ConvertTo-Json -Compress
    try {
        Add-Content -LiteralPath (Join-Path $d ((Get-Date).ToString('yyyy-MM-dd') + '.log')) -Value $line -Encoding UTF8
    }
    catch {}
}

function Sync-MediaLogs($cfg, $extMap, $useEverything) {
    $snapPath = Get-LogSnapshotPath $cfg
    $prev = @()
    if (Test-Path -LiteralPath $snapPath) {
        try { $prev = @(Get-Content -LiteralPath $snapPath -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ }) } catch { $prev = @() }
    }
    $curr = @(Get-MediaSnapshot $cfg $extMap $useEverything)
    try {
        $tmp = "$snapPath.tmp"
        @($curr) | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $snapPath -Force
    }
    catch {}
    if (@($prev).Count -eq 0) { return @() }
    $events = @(Compare-MediaSnapshots $prev $curr)
    foreach ($e in $events) { Write-MediaLog $cfg $e }
    return $events
}

function Read-LogFile($cfg, $dateStr, $maxLines) {
    if (-not $dateStr) { $dateStr = (Get-Date).ToString('yyyy-MM-dd') }
    if ($dateStr -notmatch '^\d{4}-\d{2}-\d{2}$') { return @() }
    $f = Join-Path (Get-LogDir $cfg) "$dateStr.log"
    $out = New-Object System.Collections.ArrayList
    if (Test-Path -LiteralPath $f) {
        foreach ($line in @(Get-Content -LiteralPath $f -Tail ([Math]::Max(1, $maxLines)) -Encoding UTF8)) {
            try {
                $j = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($j) { [void]$out.Add($j) }
            }
            catch {}
        }
    }
    return @($out)
}

function Get-LogDates($cfg) {
    $d = Get-LogDir $cfg
    return @(Get-ChildItem -LiteralPath $d -Filter '*.log' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName } | Sort-Object -Descending)
}

function Clean-LogFiles($cfg) {
    $keep = 30
    if ($null -ne $cfg.logKeepDays) { $keep = [int]$cfg.logKeepDays }
    if ($keep -lt 1) { $keep = 1 }
    $cut = (Get-Date).AddDays(-$keep)
    foreach ($f in @(Get-ChildItem -LiteralPath (Get-LogDir $cfg) -Filter '*.log' -File -ErrorAction SilentlyContinue)) {
        if ($f.LastWriteTime -lt $cut) { try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue } catch {} }
    }
}

function Get-EntryForPath($entries, $fullPath) {
    if (-not $entries) { return $null }
    $p = $fullPath.ToLower()
    $best = $null
    $bestLen = -1
    foreach ($e in $entries) {
        $root = [string]$e.Path
        if (-not $root) { continue }
        $rootL = $root.ToLowerInvariant().TrimEnd('\')
        if ($p.StartsWith($rootL)) {
            if ($rootL.Length -gt $bestLen) { $bestLen = $rootL.Length; $best = $e }
        }
    }
    return $best
}

function Test-PathRules($entry, $fullPath) {
    if (-not $entry) { return $true }
    $p = $fullPath.ToLower()
    $inc = @($entry.Include)
    if ($inc.Count -gt 0) {
        $ok = $false
        foreach ($k in $inc) {
            if ($p.Contains([string]$k.ToLower())) { $ok = $true; break }
        }
        if (-not $ok) { return $false }
    }
    $exc = @($entry.Exclude)
    foreach ($k in $exc) {
        if ($p.Contains([string]$k.ToLower())) { return $false }
    }
    return $true
}

function Add-IndexEntry($list, $path, $extMap, $entries) {
    if (-not $path) { return }
    if ($entries) {
        $entry = Get-EntryForPath $entries $path
        if ($entry -and -not (Test-PathRules $entry $path)) { return }
    }
    $ext = [IO.Path]::GetExtension($path).ToLower()
    if (-not $extMap.ContainsKey($ext)) { return }
    $type = $extMap[$ext]
    $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
    if (-not $item) { return }
    $entry = [PSCustomObject]@{
        Name = $item.Name
        FullPath = $item.FullName
        Extension = $ext
        Type = $type
        Size = $item.Length
        LastWriteTime = $item.LastWriteTime
        CreatedTime = $item.CreationTime
    }
    $idx = -1
    for ($i = 0; $i -lt $list.Count; $i++) {
        if ($list[$i].FullPath -eq $path) { $idx = $i; break }
    }
    if ($idx -ge 0) { $list[$idx] = $entry }
    else { $list.Add($entry) | Out-Null }
}

function Invoke-FullScan($cfg, $extMap) {
    $list = New-Object System.Collections.ArrayList
    $start = Get-Date
    $entries = Resolve-WatchConfig $cfg
    foreach ($e in $entries) {
        $p = $e.Path
        if (-not (Test-Path -LiteralPath $p)) { Write-Host "跳过不存在: $p"; continue }
        Write-Host "扫描 $p ..."
        Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            Add-IndexEntry $list $_.FullName $extMap $entries
        }
    }
    $secs = ((Get-Date) - $start).TotalSeconds
    Save-Index (Get-IndexFile $cfg) $list
    $msg = "完成: 共 $($list.Count) 个媒体文件, 用时 $([math]::Round($secs,1)) 秒"
    Write-Host $msg
    return [pscustomobject]@{
        Count = $list.Count
        Seconds = [math]::Round($secs, 1)
        Message = $msg
    }
}

function Convert-ToDate($s, $asSince) {
    if (-not $s) { return $null }
    $m = [regex]::Match($s, '^(\d+)([dhwm]?)$')
    if ($m.Success) {
        $n = [int]$m.Groups[1].Value
        $u = $m.Groups[2].Value
        if ($asSince) {
            switch ($u) {
                'h' { $span = New-TimeSpan -Hours $n }
                'm' { $span = New-TimeSpan -Minutes $n }
                'w' { $span = New-TimeSpan -Days ($n * 7) }
                default { $span = New-TimeSpan -Days $n }
            }
            return ((Get-Date) - $span)
        }
    }
    $dt = [datetime]::MinValue
    if ([datetime]::TryParse($s, [ref]$dt)) { return $dt }
    return $null
}

function Get-Category($cfg, $fullPath) {
    if (-not $cfg -or -not $cfg.categories) { return $null }
    $name = Split-Path -Leaf $fullPath
    $pl = $fullPath.ToLower()
    $nl = $name.ToLower()
    foreach ($rule in $cfg.categories) {
        $rname = [string]$rule.name
        if (-not $rname) { continue }
        $match = [string]$rule.match
        if (-not $match) { $match = 'both' }
        $kw = @($rule.keywords | ForEach-Object { [string]$_ })
        foreach ($k in $kw) {
            $kl = $k.ToLower()
            if (-not $kl) { continue }
            $inName = $nl.Contains($kl)
            $inPath = $pl.Contains($kl)
            if ($match -eq 'name' -and $inName) { return $rname }
            if ($match -eq 'path' -and $inPath) { return $rname }
            if ($match -ne 'name' -and $match -ne 'path' -and ($inName -or $inPath)) { return $rname }
        }
    }
    return $null
}

function Apply-CategoryQuota($items, $cfg, $perCat) {
    if ($null -eq $perCat -or $perCat -le 0) { $perCat = 100 }
    $groups = @{}
    $counts = @{}
    foreach ($it in @($items)) {
        $cat = $it.category
        if (-not $cat) { $cat = '其他' }
        if (-not $groups.ContainsKey($cat)) { $groups[$cat] = New-Object System.Collections.ArrayList; $counts[$cat] = 0 }
        $counts[$cat]++
        if ($groups[$cat].Count -lt $perCat) { [void]$groups[$cat].Add($it) }
    }
    $cats = @($groups.Keys | Sort-Object)
    if ($cats -contains '其他') {
        $cats = @($cats | Where-Object { $_ -ne '其他' }) + @('其他')
    }
    $out = New-Object System.Collections.ArrayList
    foreach ($c in $cats) {
        foreach ($it in $groups[$c]) { [void]$out.Add($it) }
    }
    return [pscustomobject]@{
        Total = @($items).Count
        Categories = @($cats | ForEach-Object { [pscustomobject]@{ name = $_; count = $counts[$_] } })
        Items = @($out)
    }
}

function Invoke-Search($list, $keyword, $type, $since, $from, $to) {
    $kw = $null
    if (-not [string]::IsNullOrEmpty($keyword)) { $kw = $keyword }
    $tp = $null
    if (-not [string]::IsNullOrEmpty($type)) { $tp = $type }
    $res = @($list | Where-Object {
        ($null -eq $kw -or $_.Name -like "*$kw*" -or $_.FullPath -like "*$kw*") -and
        ($null -eq $tp -or $_.Type -eq $tp) -and
        ($null -eq $since -or $_.LastWriteTime -ge $since) -and
        ($null -eq $from -or $_.LastWriteTime -ge $from) -and
        ($null -eq $to -or $_.LastWriteTime -le $to)
    })
    return @($res | Sort-Object LastWriteTime -Descending)
}

# ============ Everything 实时索引提供者 ============
$script:EsLoaded = $false
$script:EsAvailable = $false
$script:EsDll = ''

function Get-EsCSharpSource {
    return @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class MFEs {
    [DllImport("%DLL%", CharSet = CharSet.Unicode)]
    private static extern void Everything_SetSearchW(string s);
    [DllImport("%DLL%")]
    private static extern void Everything_SetMatchPath(bool b);
    [DllImport("%DLL%")]
    private static extern void Everything_SetMatchCase(bool b);
    [DllImport("%DLL%")]
    private static extern void Everything_SetMatchWholeWord(bool b);
    [DllImport("%DLL%")]
    private static extern void Everything_SetRegex(bool b);
    [DllImport("%DLL%")]
    private static extern void Everything_SetMax(uint m);
    [DllImport("%DLL%")]
    private static extern void Everything_SetSort(uint s);
    [DllImport("%DLL%")]
    private static extern void Everything_SetRequestFlags(uint f);
    [DllImport("%DLL%")]
    private static extern bool Everything_QueryW(bool w);
    [DllImport("%DLL%")]
    private static extern uint Everything_GetNumResults();
    [DllImport("%DLL%", CharSet = CharSet.Unicode)]
    private static extern uint Everything_GetResultFullPathNameW(uint i, StringBuilder b, uint n);
    [DllImport("%DLL%")]
    private static extern bool Everything_GetResultSize(uint i, out long s);
    [DllImport("%DLL%")]
    private static extern bool Everything_GetResultDateModified(uint i, out long t);
    [DllImport("%DLL%")]
    private static extern bool Everything_GetResultDateCreated(uint i, out long t);
    [DllImport("%DLL%")]
    private static extern void Everything_Exit();

    private const uint REQ = 0x00000001 | 0x00000002 | 0x00000004 | 0x00000010 | 0x00000020 | 0x00000040;
    private const uint SORT_DM_DESC = 14;

    public static void Exit() {
        try { Everything_Exit(); } catch { }
    }

    public static bool Available() {
        try {
            Everything_SetSearchW("");
            Everything_SetMax(1);
            Everything_SetRequestFlags(REQ);
            return Everything_QueryW(true);
        } catch { return false; }
    }

    public static string[] Query(string search) {
        Everything_SetSearchW(search == null ? "" : search);
        Everything_SetMatchPath(false);
        Everything_SetMatchCase(false);
        Everything_SetMatchWholeWord(false);
        Everything_SetRegex(false);
        Everything_SetMax(0x7FFFFFFF);
        Everything_SetSort(SORT_DM_DESC);
        Everything_SetRequestFlags(REQ);
        if (!Everything_QueryW(true)) return new string[0];
        uint n = Everything_GetNumResults();
        string[] r = new string[n];
        for (uint i = 0; i < n; i++) {
            StringBuilder sb = new StringBuilder(4096);
            Everything_GetResultFullPathNameW(i, sb, 4096);
            long size = 0, dm = 0, dc = 0;
            Everything_GetResultSize(i, out size);
            Everything_GetResultDateModified(i, out dm);
            Everything_GetResultDateCreated(i, out dc);
            r[i] = sb.ToString() + "\t" + size.ToString() + "\t" + dm.ToString() + "\t" + dc.ToString();
        }
        return r;
    }
}
'@
}

function Initialize-EverythingConfig {
    $ini = Join-Path (Get-ScriptDir) 'Everything.ini'
    try {
        if (Test-Path -LiteralPath $ini) {
            $content = [System.IO.File]::ReadAllText($ini)
            if ($content -match 'run_as_admin\s*=\s*1') {
                $fixed = $content -replace '(?m)^\s*run_as_admin\s*=\s*1\s*$', 'run_as_admin=0'
                [System.IO.File]::WriteAllText($ini, $fixed, [System.Text.Encoding]::Unicode)
            }
            return
        }
        [System.IO.File]::WriteAllText($ini, "[Everything]`r`nrun_as_admin=0`r`n", [System.Text.Encoding]::Unicode)
    }
    catch {}
}

function Ensure-EverythingAutostart {
    $exe = Join-Path (Get-ScriptDir) 'Everything.exe'
    if (-not (Test-Path -LiteralPath $exe)) { return $false }
    try {
        Initialize-EverythingConfig
        $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        $name = 'MediaFinder-Everything'
        $cmd = '"' + $exe + '" -startup'
        $existing = (Get-ItemProperty -Path $runKey -Name $name -ErrorAction SilentlyContinue).$name
        if ($existing -ne $cmd) {
            New-ItemProperty -Path $runKey -Name $name -Value $cmd -PropertyType String -Force | Out-Null
            return $true
        }
        return $false
    }
    catch { return $false }
}

function Remove-EverythingAutostart {
    try {
        $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        Remove-ItemProperty -Path $runKey -Name 'MediaFinder-Everything' -ErrorAction SilentlyContinue
    }
    catch {}
}

function Start-EmbeddedEverything {
    if (Get-Process -Name Everything -ErrorAction SilentlyContinue) { return $false }
    $exe = Join-Path (Get-ScriptDir) 'Everything.exe'
    if (-not (Test-Path -LiteralPath $exe)) { return $false }
    try {
        Initialize-EverythingConfig
        Start-Process -FilePath $exe -ArgumentList '-startup' -WindowStyle Minimized | Out-Null
        return $true
    }
    catch { return $false }
}

function Initialize-EverythingProvider {
    param($cfg, [int]$WaitSeconds = 0)
    if ($script:EsLoaded) { return $script:EsAvailable }
    $script:EsLoaded = $true
    $script:EsStartedByUs = $false
    if ($cfg -and [string]$cfg.indexProvider -eq 'ps') { return $false }
    if (-not [Environment]::Is64BitProcess) { return $false }
    $cand = New-Object System.Collections.ArrayList
    [void]$cand.Add((Join-Path (Get-ScriptDir) 'Everything64.dll'))
    if ($cfg -and $cfg.everythingDllPath) { [void]$cand.Add([string]$cfg.everythingDllPath) }
    $g = Get-Command Everything64.dll -ErrorAction SilentlyContinue
    if ($g) { [void]$cand.Add($g.Source) }
    foreach ($c in @($cand | Select-Object -Unique)) {
        if ($c -and (Test-Path -LiteralPath $c)) { $script:EsDll = $c; break }
    }
    if (-not $script:EsDll) { return $false }
    try {
        $escaped = $script:EsDll.Replace('\', '\\').Replace('"', '\"')
        $src = (Get-EsCSharpSource).Replace('%DLL%', $escaped)
        Add-Type -TypeDefinition $src
        if ($cfg -and $cfg.autoStartEverything -ne $false) {
            $script:EsStartedByUs = Start-EmbeddedEverything
        }
        $deadline = (Get-Date).AddSeconds($WaitSeconds)
        $noProcTries = 0
        do {
            $script:EsAvailable = [MFEs]::Available()
            if ($script:EsAvailable) { break }
            if ($script:EsStartedByUs -and -not (Get-Process -Name Everything -ErrorAction SilentlyContinue)) {
                $noProcTries++
                if ($noProcTries -ge 10) { break }
            }
            Start-Sleep -Milliseconds 500
        } while ((Get-Date) -lt $deadline)
    }
    catch { $script:EsAvailable = $false }
    return $script:EsAvailable
}

function Invoke-ESQuery {
    param([string]$Search)
    if (-not $script:EsAvailable) { return @() }
    try { return @([MFEs]::Query($Search)) } catch { return @() }
}

function ConvertFrom-ESLine {
    param($Line, $extMap)
    $p = $Line.Split("`t")
    if ($p.Count -lt 4) { return $null }
    $path = $p[0]
    if (-not $path) { return $null }
    $ext = [IO.Path]::GetExtension($path).ToLower()
    if (-not $extMap.ContainsKey($ext)) { return $null }
    $size = 0L; $dm = 0L; $dc = 0L
    [int64]::TryParse($p[1], [ref]$size) | Out-Null
    [int64]::TryParse($p[2], [ref]$dm) | Out-Null
    [int64]::TryParse($p[3], [ref]$dc) | Out-Null
    return [pscustomobject]@{
        Name = Split-Path -Leaf $path
        FullPath = $path
        Extension = $ext
        Type = $extMap[$ext]
        Size = $size
        LastWriteTime = if ($dm -ne 0) { [DateTime]::FromFileTime($dm) } else { [DateTime]::MinValue }
        CreatedTime = if ($dc -ne 0) { [DateTime]::FromFileTime($dc) } else { [DateTime]::MinValue }
    }
}

function Build-ESEntrySearch {
    param($Entry, $extMap, $Type, $Keyword, $SinceDate)
    $parts = New-Object System.Collections.ArrayList
    [void]$parts.Add(('path:"' + $Entry.Path + '"'))
    if ($Type) { $exts = @($extMap.GetEnumerator() | Where-Object { $_.Value -eq $Type } | ForEach-Object { $_.Key }) }
    else { $exts = @($extMap.Keys) }
    [void]$parts.Add(('ext:' + (($exts | ForEach-Object { $_.TrimStart('.') }) -join ';')))
    if ($Keyword) { [void]$parts.Add(('"' + ($Keyword -replace '"', '') + '"')) }
    if ($SinceDate) { [void]$parts.Add(('dm:' + $SinceDate.ToString('yyyy-MM-dd') + '..')) }
    foreach ($x in @($Entry.Exclude)) { if ($x) { [void]$parts.Add(('!' + $x)) } }
    return ($parts -join ' ')
}

function Search-Everything {
    param($cfg, $extMap, $entries, $Keyword, $Type, $SinceDate, $Limit)
    $results = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($e in @($entries)) {
        $base = Build-ESEntrySearch $e $extMap $Type $Keyword $SinceDate
        $incs = @($e.Include)
        $searches = @()
        if ($incs.Count -eq 0) { $searches = @($base) }
        else {
            foreach ($k in $incs) { if ($k) { $searches += ($base + ' "' + ($k -replace '"', '') + '"') } }
        }
        foreach ($s in $searches) {
            foreach ($line in @(Invoke-ESQuery $s)) {
                $r = ConvertFrom-ESLine $line $extMap
                if (-not $r) { continue }
                $k = $r.FullPath.ToLower()
                if ($seen.ContainsKey($k)) { continue }
                $seen[$k] = $true
                [void]$results.Add($r)
            }
        }
    }
    $sorted = @($results | Sort-Object LastWriteTime -Descending)
    if ($null -ne $Limit -and $Limit -gt 0) { $sorted = @($sorted | Select-Object -First $Limit) }
    return $sorted
}

function Get-EverythingCount {
    param($cfg, $extMap)
    $entries = Resolve-WatchConfig $cfg
    $total = 0
    foreach ($e in @($entries)) {
        $base = Build-ESEntrySearch $e $extMap $null $null $null
        $incs = @($e.Include)
        if ($incs.Count -eq 0) { $total += @(Invoke-ESQuery $base).Count }
        else {
            foreach ($k in $incs) { if ($k) { $total += @(Invoke-ESQuery ($base + ' "' + $k + '"')).Count } }
        }
    }
    return $total
}

function Invoke-ESFullScan {
    param($cfg, $extMap)
    $start = Get-Date
    $entries = Resolve-WatchConfig $cfg
    $list = @(Search-Everything $cfg $extMap $entries $null $null $null $null)
    $arr = New-Object System.Collections.ArrayList
    foreach ($x in $list) { [void]$arr.Add($x) }
    Save-Index (Get-IndexFile $cfg) $arr
    $secs = ((Get-Date) - $start).TotalSeconds
    $msg = "完成: 共 $($arr.Count) 个媒体文件, 用时 $([math]::Round($secs,2)) 秒 (Everything 实时索引)"
    Write-Host $msg
    return [pscustomobject]@{
        Count = $arr.Count
        Seconds = [math]::Round($secs, 2)
        Message = $msg
    }
}
