[CmdletBinding()]
param(
    [int]$Port = 8765,
    [string]$Config = "",
    [switch]$NoBrowser
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$script:ServerDir = $PSScriptRoot
$script:LogPath = Join-Path $script:ServerDir 'MediaFinderServer.log'
function Log($msg) {
    try {
        Add-Content -LiteralPath $script:LogPath -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    catch {}
}
try { Clear-Content -LiteralPath $script:LogPath -ErrorAction SilentlyContinue } catch {}
Log "启动开始, PSScriptRoot=$($script:ServerDir), Port=$Port"

. (Join-Path $script:ServerDir 'MediaFinder.Core.ps1')
$script:WebDir = Join-Path $script:ServerDir 'web'
$script:PollerPS = $null
$script:Port = $Port

try {
    $cfg = Get-Config $Config
    $script:CfgPath = $script:CfgPath
    $extMap = Build-ExtMap $cfg
    $script:StopRequested = $false
}
catch {
    Log "初始化失败: $($_.Exception.Message)"
    Write-Host "初始化失败: $($_.Exception.Message)"
    exit 1
}

$script:IndexMode = 'ps'
if (Initialize-EverythingProvider $cfg 30) {
    $script:IndexMode = 'everything'
    Log "索引模式: Everything 实时索引 ($script:EsDll)"
    if ($script:EsStartedByUs) { Log "Everything 由 MediaFinder 自动启动" }
    if ($cfg.autostartEverythingOnBoot -ne $false) {
        if (Ensure-EverythingAutostart) { Log "已添加 Everything 开机自启 (注册表 Run)" }
    }
}
else {
    Log "索引模式: PowerShell 扫描 (Everything 不可用或 indexProvider=ps)"
}
Log "初始化完成, 配置: $script:CfgPath"

function Send-Json($ctx, $obj) {
    $json = $obj | ConvertTo-Json -Depth 6 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $ctx.Response.ContentType = 'application/json; charset=utf-8'
    $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.Close()
}

function Send-File($ctx, $path, $mime) {
    if (-not (Test-Path -LiteralPath $path)) {
        $ctx.Response.StatusCode = 404
        $ctx.Response.Close()
        return
    }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $ctx.Response.ContentType = $mime
    $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.Close()
}

function Send-Empty($ctx, $code) {
    $ctx.Response.StatusCode = $code
    $ctx.Response.Close()
}

Add-Type -AssemblyName System.Drawing

$script:ffmpeg = $null
function Find-FFmpeg {
    if ($null -ne $script:ffmpeg) { return $script:ffmpeg }
    $c = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($c) { $script:ffmpeg = $c.Source }
    else { $script:ffmpeg = '' }
    return $script:ffmpeg
}

function New-ImageThumb($src, $dest, $maxSize) {
    $img = $null; $bmp = $null; $g = $null
    try {
        $img = [System.Drawing.Image]::FromFile($src)
        $ratio = [Math]::Min(1.0, $maxSize / [double][Math]::Max($img.Width, $img.Height))
        $w = [Math]::Max(1, [int]($img.Width * $ratio))
        $h = [Math]::Max(1, [int]($img.Height * $ratio))
        $bmp = New-Object System.Drawing.Bitmap($w, $h)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.Clear([System.Drawing.Color]::White)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.DrawImage($img, 0, 0, $w, $h)
        $bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        return $true
    }
    catch { return $false }
    finally {
        if ($g) { $g.Dispose() }
        if ($bmp) { $bmp.Dispose() }
        if ($img) { $img.Dispose() }
    }
}

function Invoke-VideoThumb-Worker($src, $dest, $size) {
    $worker = Join-Path $script:ServerDir 'MediaFinder-thumb.ps1'
    if (-not (Test-Path -LiteralPath $worker)) { return $false }
    try {
        $p = Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$worker`"",'-Src',"`"$src`"",'-Dest',"`"$dest`"",'-Size',"$size" -PassThru -WindowStyle Hidden
        if (-not $p.WaitForExit(25000)) { try { $p.Kill() } catch {} }
        return (Test-Path -LiteralPath $dest)
    }
    catch { return $false }
}

function Send-Thumbnail($ctx, $target, $size) {
    if (-not $target -or -not (Test-Path -LiteralPath $target -PathType Leaf)) { Send-Empty $ctx 404; return }
    if ($size -lt 40) { $size = 40 }
    if ($size -gt 640) { $size = 640 }
    $ext = [IO.Path]::GetExtension($target).ToLower()
    $imgExts = @('.png','.jpg','.jpeg','.bmp','.gif','.tiff','.jfif')
    $vidExts = @('.mp4','.mkv','.mov','.avi','.ts','.flv','.webm','.m4v','.m2ts','.wmv','.mpg','.mpeg')
    $isImg = $imgExts -contains $ext
    $isVid = $vidExts -contains $ext
    if (-not ($isImg -or $isVid)) { Send-Empty $ctx 204; return }
    $cacheDir = Join-Path $env:LOCALAPPDATA 'MediaFinder-thumbs'
    try {
        if (-not (Test-Path -LiteralPath $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
    }
    catch { Send-Empty $ctx 500; return }
    $fi = Get-Item -LiteralPath $target -ErrorAction SilentlyContinue
    if (-not $fi) { Send-Empty $ctx 404; return }
    $keyRaw = "$target|$($fi.LastWriteTimeUtc.Ticks)|$size"
    $key = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($keyRaw)).TrimEnd('=').Replace('+','-').Replace('/','_')
    $cacheFile = Join-Path $cacheDir "$key.jpg"
    if (-not (Test-Path -LiteralPath $cacheFile)) {
        $ok = $false
        try {
            if ($isImg) { $ok = New-ImageThumb $target $cacheFile $size }
            else { $ok = Invoke-VideoThumb-Worker $target $cacheFile $size }
        }
        catch { $ok = $false }
        if (-not $ok) { Send-Empty $ctx 204; return }
    }
    Send-File $ctx $cacheFile 'image/jpeg'
}

function Read-Body($ctx) {
    $reader = New-Object System.IO.StreamReader($ctx.Request.InputStream, [System.Text.Encoding]::UTF8)
    $text = $reader.ReadToEnd()
    $reader.Close()
    if ($text) { return ($text | ConvertFrom-Json -ErrorAction SilentlyContinue) }
    return $null
}

function Get-IndexStats($cfg) {
    if ($script:IndexMode -eq 'everything') {
        $extMap = Build-ExtMap $cfg
        return [pscustomobject]@{
            count = (Get-EverythingCount $cfg $extMap)
            modified = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            file = $null
            live = $true
        }
    }
    $idxPath = Get-IndexFile $cfg
    $count = 0
    $modified = $null
    if (Test-Path -LiteralPath $idxPath) {
        $f = Get-Item -LiteralPath $idxPath
        $modified = $f.LastWriteTime
        $idxList = Load-Index $idxPath
        $count = $idxList.Count
    }
    return [pscustomobject]@{
        count = $count
        modified = if ($modified) { $modified.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
        file = $idxPath
    }
}

$script:PollerScript = {
    $core = $args[0]
    $cfgPath = $args[1]
    $interval = $args[2]
    $state = $args[3]
    . $core
    $known = @{}
    $list = New-Object System.Collections.ArrayList
    $idxPath = $null
    try {
        $cfg = Get-Config $cfgPath
        $idxPath = Get-IndexFile $cfg
        $list = Load-Index $idxPath
        foreach ($x in $list) { $known[$x.FullPath.ToLower()] = $true }
    }
    catch {}
    while ($state.Running) {
        Start-Sleep -Seconds $interval
        if (-not $state.Running) { break }
        try {
            $cfg = Get-Config $cfgPath
            $extMap = Build-ExtMap $cfg
            $entries = Resolve-WatchConfig $cfg
            $list = Load-Index $idxPath
            $seen = @{}
            $changed = $false
            foreach ($e in $entries) {
                if (-not (Test-Path -LiteralPath $e.Path -PathType Container)) { continue }
                Get-ChildItem -LiteralPath $e.Path -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                    $key = $_.FullName.ToLower()
                    $seen[$key] = $true
                    if ($known.ContainsKey($key)) { return }
                    $known[$key] = $true
                    Add-IndexEntry $list $_.FullName $extMap $entries
                    $changed = $true
                }
            }
            foreach ($k in @($known.Keys)) {
                if (-not $seen.ContainsKey($k)) {
                    $list = New-Object System.Collections.ArrayList
                    foreach ($x in (Load-Index $idxPath)) {
                        if ($x.FullPath.ToLower() -ne $k) { $list.Add($x) | Out-Null }
                    }
                    $known.Remove($k)
                    $changed = $true
                }
            }
            if ($changed) { Save-Index $idxPath $list }
            if ($changed) {
                try {
                    $c2 = Get-Config $cfgPath
                    $em2 = Build-ExtMap $c2
                    if ($c2.logEnabled -ne $false) { [void](Sync-MediaLogs $c2 $em2 $false) }
                }
                catch {}
            }
        }
        catch {}
    }
}

$script:LogMonitorScript = {
    $core = $args[0]
    $cfgPath = $args[1]
    $interval = $args[2]
    $state = $args[3]
    . $core
    $esDll = [string]$env:MF_ES_DLL
    if ($esDll -and (Test-Path -LiteralPath $esDll)) {
        try {
            $script:EsDll = $esDll
            $escaped = $esDll.Replace('\', '\\').Replace('"', '\"')
            $src = (Get-EsCSharpSource).Replace('%DLL%', $escaped)
            Add-Type -TypeDefinition $src
            $script:EsAvailable = [MFEs]::Available()
        }
        catch { $script:EsAvailable = $false }
    }
    while ($state.Running) {
        Start-Sleep -Seconds $interval
        if (-not $state.Running) { break }
        try {
            $cfg = Get-Config $cfgPath
            $extMap = Build-ExtMap $cfg
            if ($cfg.logEnabled -eq $false) { continue }
            [void](Sync-MediaLogs $cfg $extMap $true)
        }
        catch {}
    }
}

function Start-LogMonitor {
    if ($script:LogMonitorPS) { return }
    if ($script:IndexMode -ne 'everything') { return }
    $cfgL = Get-Config $script:CfgPath
    if ($cfgL.logEnabled -eq $false) {
        Log "活动日志: 已停用"
        return
    }
    $core = Join-Path $script:ServerDir 'MediaFinder.Core.ps1'
    $cfgPath = $script:CfgPath
    $interval = 30
    if ($null -ne $cfgL.logIntervalSeconds) { $interval = [int]$cfgL.logIntervalSeconds }
    if ($interval -lt 5) { $interval = 5 }
    try { Clean-LogFiles $cfgL } catch {}
    $state = [System.Collections.Hashtable]::Synchronized(@{ Running = $true })
    $script:LogMonitorState = $state
    $script:LogMonitorPS = [System.Management.Automation.PowerShell]::Create()
    $esDllArg = Join-Path $script:ServerDir 'Everything64.dll'
    if (-not (Test-Path -LiteralPath $esDllArg)) { $esDllArg = [string]$script:EsDll }
    $env:MF_ES_DLL = $esDllArg
    [void]$script:LogMonitorPS.AddScript($script:LogMonitorScript).AddArgument($core).AddArgument($cfgPath).AddArgument($interval).AddArgument($state)
    [void]$script:LogMonitorPS.BeginInvoke()
    Log "活动日志监控已启动 (间隔 ${interval}秒, dll=$esDllArg)"
}

function Stop-LogMonitor {
    if ($script:LogMonitorState) { $script:LogMonitorState.Running = $false }
    $ps = $script:LogMonitorPS
    $script:LogMonitorPS = $null
    $script:LogMonitorState = $null
    if ($ps) {
        try { $ps.Stop() } catch {}
        try { $ps.Dispose() } catch {}
    }
}

function Start-Poller {
    if ($script:IndexMode -eq 'everything') {
        Log "Everything 模式: 索引实时更新, 无需轮询扫描"
        return
    }
    if ($script:PollerPS) { return }
    $core = Join-Path $script:ServerDir 'MediaFinder.Core.ps1'
    $cfgPath = $script:CfgPath
    $cfgP = Get-Config $cfgPath
    $interval = 2
    if ($cfgP.refreshInterval) { $interval = [int]$cfgP.refreshInterval }
    if ($interval -lt 1) { $interval = 1 }
    $state = [System.Collections.Hashtable]::Synchronized(@{ Running = $true })
    $script:PollerState = $state
    $script:PollerPS = [System.Management.Automation.PowerShell]::Create()
    [void]$script:PollerPS.AddScript($script:PollerScript).AddArgument($core).AddArgument($cfgPath).AddArgument($interval).AddArgument($state)
    [void]$script:PollerPS.BeginInvoke()
    Log "自动刷新已启动 (间隔 ${interval}秒)"
}

function Stop-Poller {
    if ($script:PollerState) {
        $script:PollerState.Running = $false
    }
    $ps = $script:PollerPS
    $script:PollerPS = $null
    $script:PollerState = $null
    if ($ps) {
        try { $ps.Stop() } catch {}
        try { $ps.Dispose() } catch {}
    }
    Log "自动刷新已停止"
}

function Get-MonitorState {
    return [pscustomobject]@{
        running = $null -ne $script:PollerPS
        pid = $null
    }
}

function Ensure-Shortcut {
    $lnk = Join-Path $script:ServerDir 'MediaFinder.lnk'
    $target = Join-Path $script:ServerDir 'MediaFinder-web.cmd'
    $ico = Join-Path $script:ServerDir 'MediaFinder.ico'
    $need = $false
    if (-not (Test-Path -LiteralPath $lnk)) {
        $need = $true
    }
    else {
        try {
            $ws = New-Object -ComObject WScript.Shell
            $sc = $ws.CreateShortcut($lnk)
            if ($sc.TargetPath -ne $target -or -not (Test-Path -LiteralPath $sc.TargetPath)) { $need = $true }
        }
        catch { $need = $true }
    }
    if ($need) {
        try {
            $ws = New-Object -ComObject WScript.Shell
            $sc = $ws.CreateShortcut($lnk)
            $sc.TargetPath = $target
            $sc.WorkingDirectory = $script:ServerDir
            $sc.Description = 'MediaFinder 媒体查找工具'
            if (Test-Path -LiteralPath $ico) { $sc.IconLocation = "$ico,0" }
            $sc.Save()
            Log "已生成快捷方式: $lnk"
        }
        catch { Log "生成快捷方式失败: $($_.Exception.Message)" }
    }
}

function Save-ConfigFile($cfgObj, $cfgPath) {
    $cfgObj | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $cfgPath -Encoding UTF8
}

function Get-SubDirs($path) {
    $path = [string]$path
    if (-not $path) {
        $dirs = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root } | Where-Object { $_ })
        return [pscustomobject]@{ current = ''; parent = $null; dirs = $dirs }
    }
    if ($path -match '^[a-zA-Z]:$') { $path = $path + '\' }
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        return [pscustomobject]@{ current = $path; parent = $null; dirs = @() }
    }
    $dirs = @(Get-ChildItem -LiteralPath $path -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    $parent = Split-Path -Parent $path
    if ($null -eq $parent) { $parent = '' }
    return [pscustomobject]@{ current = $path; parent = $parent; dirs = $dirs }
}

function Get-PathSuggestions($keyword) {
    $results = New-Object System.Collections.ArrayList
    $kw = ([string]$keyword).ToLower().Trim()
    if (-not $kw) {
        $u = $env:USERPROFILE
        $common = @(
            (Join-Path $u 'Pictures\Screenshots'),
            (Join-Path $u 'Videos\Captures'),
            (Join-Path $u 'Pictures'),
            (Join-Path $u 'Downloads')
        )
        foreach ($c in $common) {
            if (Test-Path -LiteralPath $c) {
                $results.Add([pscustomobject]@{ path = $c; kind = '常用位置' }) | Out-Null
            }
        }
        return ,@($results | Select-Object -First 20)
    }
    $roots = @()
    $roots += @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root } | Where-Object { $_ })
    if ($env:USERPROFILE) { $roots += $env:USERPROFILE }
    $roots = @($roots | Select-Object -Unique)
    foreach ($r in $roots) {
        $lvl1 = @(Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue)
        foreach ($dir in $lvl1) {
            $cand = $null
            if ($dir.Name.ToLower().Contains($kw)) { $cand = $dir.FullName }
            if (-not $cand) {
                $lvl2 = @(Get-ChildItem -LiteralPath $dir.FullName -Directory -ErrorAction SilentlyContinue)
                foreach ($d2 in $lvl2) {
                    if ($d2.Name.ToLower().Contains($kw)) { $cand = $d2.FullName; break }
                }
            }
            if (-not $cand) {
                $dl = $dir.Name.ToLower()
                if ($dl -in @('wegameapps','steamlibrary','steam','epic games')) {
                    foreach ($sub in @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -Directory -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match 'rail_apps|common_apps|steamapps' } | Select-Object -First 40)) {
                        $sub2 = @(Get-ChildItem -LiteralPath $sub.FullName -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name.ToLower().Contains($kw) } | Select-Object -First 5)
                        foreach ($s2 in $sub2) { $cand = $s2.FullName; break }
                        if ($cand) { break }
                    }
                }
            }
            if ($cand) {
                $screens = @(Get-ChildItem -LiteralPath $cand -Recurse -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'screen|saved|截图|capture' } | Select-Object -First 12)
                if ($screens.Count -gt 0) {
                    foreach ($s in $screens) {
                        $results.Add([pscustomobject]@{ path = $s.FullName; kind = '截图文件夹' }) | Out-Null
                    }
                }
                else {
                    $results.Add([pscustomobject]@{ path = $cand; kind = '文件夹' }) | Out-Null
                }
            }
        }
    }
    return ,@($results | Select-Object -First 30)
}

function Handle-Request($ctx) {
    # 反 CSRF: 仅允许本机来源 (localhost/127.0.0.1/[::1])
    try {
        $hostHdr = [string]$ctx.Request.Headers['Host']
        if ($hostHdr) {
            $hn = ($hostHdr -split ':')[0].Trim().Trim('[', ']').ToLower()
            if ($hn -and $hn -notin @('localhost', '127.0.0.1', '::1')) { Send-Empty $ctx 403; return }
        }
        $origin = [string]$ctx.Request.Headers['Origin']
        if ($origin) {
            $oh = $null
            try { $oh = [System.Uri]$origin } catch { $oh = $null }
            $ohn = if ($oh) { $oh.Host.Trim().Trim('[', ']').ToLower() } else { '' }
            if ($ohn -and $ohn -notin @('localhost', '127.0.0.1', '::1')) { Send-Empty $ctx 403; return }
        }
        $referer = [string]$ctx.Request.Headers['Referer']
        if ($referer) {
            $rh = $null
            try { $rh = [System.Uri]$referer } catch { $rh = $null }
            $rhn = if ($rh) { $rh.Host.Trim().Trim('[', ']').ToLower() } else { '' }
            if ($rhn -and $rhn -notin @('localhost', '127.0.0.1', '::1')) { Send-Empty $ctx 403; return }
        }
    }
    catch { Send-Empty $ctx 403; return }
    $cfg = Get-Config $script:CfgPath
    $extMap = Build-ExtMap $cfg
    $url = $ctx.Request.Url
    $path = $url.AbsolutePath
    $method = $ctx.Request.HttpMethod

    if ($path -eq '/' -or $path -eq '/index.html') {
        Send-File $ctx (Join-Path $script:WebDir 'index.html') 'text/html; charset=utf-8'
        return
    }
    if ($path -eq '/style.css') { Send-File $ctx (Join-Path $script:WebDir 'style.css') 'text/css; charset=utf-8'; return }
    if ($path -eq '/app.js') { Send-File $ctx (Join-Path $script:WebDir 'app.js') 'application/javascript; charset=utf-8'; return }
    if ($path -eq '/favicon.ico') { Send-Empty $ctx 204; return }

    if ($path -eq '/api/status') {
        Send-Json $ctx ([pscustomobject]@{
            ok = $true
            indexMode = $script:IndexMode
            watchPaths = @((Resolve-WatchConfig $cfg) | Where-Object { Test-Path -LiteralPath $_.Path } | ForEach-Object { $_.Path })
            privacyDirs = @(Find-PrivacyDirs $cfg | ForEach-Object { $_ })
            index = Get-IndexStats $cfg
            monitor = Get-MonitorState
            configFile = $script:CfgPath
        })
        return
    }

    if ($path -eq '/api/thumb') {
        $target = $null
        $size = 160
        $q = $url.Query
        if ($q) {
            foreach ($part in ($q.TrimStart('?') -split '&')) {
                $kv = $part -split '=', 2
                if ($kv.Count -eq 2) {
                    $k = $kv[0]
                    $v = [System.Uri]::UnescapeDataString($kv[1])
                    if ($k -eq 'path') { $target = $v }
                    elseif ($k -eq 'size') { $sz = 0; if ([int]::TryParse($v, [ref]$sz)) { $size = $sz } }
                }
            }
        }
        Send-Thumbnail $ctx $target $size
        return
    }

    if ($path -eq '/api/browse' -and $method -eq 'POST') {
        $body = Read-Body $ctx
        $p = if ($body) { [string]$body.path } else { '' }
        $res = Get-SubDirs $p
        Send-Json $ctx ([pscustomobject]@{ ok = $true; current = $res.current; parent = $res.parent; dirs = @($res.dirs) })
        return
    }

    if ($path -eq '/api/suggest' -and $method -eq 'POST') {
        $body = Read-Body $ctx
        $kw = if ($body) { [string]$body.keyword } else { '' }
        $sug = Get-PathSuggestions $kw
        Send-Json $ctx ([pscustomobject]@{ ok = $true; results = @($sug) })
        return
    }

    if ($path -eq '/api/config/add' -and $method -eq 'POST') {
        $body = Read-Body $ctx
        $p = if ($body) { [string]$body.path } else { '' }
        $exc = @()
        if ($body -and $body.exclude) { $exc = @($body.exclude | ForEach-Object { [string]$_ }) }
        if ($p -and (Test-Path -LiteralPath $p)) {
            $cfg2 = Get-Config $script:CfgPath
            $cfg2.watchPaths = @(@($cfg2.watchPaths) + @($p) | Select-Object -Unique)
            if ($exc.Count -gt 0) {
                $flt = @{}
                if ($cfg2.excludeFilters) {
                    foreach ($prop in $cfg2.excludeFilters.PSObject.Properties) { $flt[$prop.Name] = @($prop.Value) }
                }
                $flt["$p"] = @($exc)
                $cfg2.excludeFilters = $flt
            }
            Save-ConfigFile $cfg2 $script:CfgPath
            Send-Json $ctx ([pscustomobject]@{ ok = $true; message = "已添加目录: $p"; watchPaths = @($cfg2.watchPaths) })
        }
        else {
            Send-Json $ctx ([pscustomobject]@{ ok = $false; error = "路径不存在: $p" })
        }
        return
    }

    if ($path -eq '/api/config/remove' -and $method -eq 'POST') {
        $body = Read-Body $ctx
        $p = if ($body) { [string]$body.path } else { '' }
        $cfg2 = Get-Config $script:CfgPath
        $cfg2.watchPaths = @(@($cfg2.watchPaths) | Where-Object { $_ -ne $p })
        Save-ConfigFile $cfg2 $script:CfgPath
        Send-Json $ctx ([pscustomobject]@{ ok = $true; message = "已移除目录: $p"; watchPaths = @($cfg2.watchPaths) })
        return
    }

    if ($path -eq '/api/config/ignore-privacy' -and $method -eq 'POST') {
        $body = Read-Body $ctx
        $p = if ($body) { [string]$body.path } else { '' }
        if ($p) {
            $cfg2 = Get-Config $script:CfgPath
            $cfg2.ignoredPrivacyDirs = @(@($cfg2.ignoredPrivacyDirs) + @($p) | Select-Object -Unique)
            Save-ConfigFile $cfg2 $script:CfgPath
            Send-Json $ctx ([pscustomobject]@{ ok = $true; message = "已忽略该目录: $p"; privacyDirs = @(Find-PrivacyDirs $cfg2 | ForEach-Object { $_ }) })
        }
        else {
            Send-Json $ctx ([pscustomobject]@{ ok = $false; error = "缺少 path 参数" })
        }
        return
    }

    if ($path -eq '/api/logs' -and $method -eq 'GET') {
        $date = $null
        $q = $url.Query
        if ($q) {
            foreach ($part in ($q.TrimStart('?') -split '&')) {
                $kv = $part -split '=', 2
                if ($kv.Count -eq 2 -and $kv[0] -eq 'date') { $date = [System.Uri]::UnescapeDataString($kv[1]) }
            }
        }
        $snapP = Get-LogSnapshotPath $cfg
        $lastCheck = $null
        if (Test-Path -LiteralPath $snapP) {
            $lastCheck = (Get-Item -LiteralPath $snapP).LastWriteTime.ToString('HH:mm:ss')
        }
        Send-Json $ctx ([pscustomobject]@{
            ok = $true
            date = if ($date) { $date } else { (Get-Date).ToString('yyyy-MM-dd') }
            enabled = ($cfg.logEnabled -ne $false)
            lastCheck = $lastCheck
            logs = @(Read-LogFile $cfg $date 300 | ForEach-Object { $_ })
        })
        return
    }

    if ($path -eq '/api/logs/dates' -and $method -eq 'GET') {
        Send-Json $ctx ([pscustomobject]@{ ok = $true; dates = @(Get-LogDates $cfg | ForEach-Object { $_ }) })
        return
    }

    if ($path -eq '/api/scan' -and $method -eq 'POST') {
        try {
            if ($script:IndexMode -eq 'everything') {
                $r = Invoke-ESFullScan $cfg $extMap
                if ($cfg.logEnabled -ne $false) {
                    try { [void](Sync-MediaLogs $cfg $extMap $true) } catch {}
                }
            }
            else {
                $r = Invoke-FullScan $cfg $extMap
                if ($cfg.logEnabled -ne $false) {
                    try {
                        $le = @(Sync-MediaLogs $cfg $extMap $false | ForEach-Object { $_ })
                        if ($le.Count -gt 0) { $r.Message = $r.Message + " (日志: $($le.Count) 个新事件)" }
                    }
                    catch {}
                }
            }
            Send-Json $ctx ([pscustomobject]@{
                ok = $true
                count = $r.Count
                seconds = $r.Seconds
                message = $r.Message
            })
        }
        catch {
            Send-Json $ctx ([pscustomobject]@{ ok = $false; error = $_.Exception.Message })
        }
        return
    }

    if ($path -eq '/api/search' -and $method -eq 'POST') {
        try {
            $body = Read-Body $ctx
            $kw = if ($body -and $body.keyword) { [string]$body.keyword } else { $null }
            $tp = if ($body -and $body.type) { [string]$body.type } else { $null }
            $sinceStr = if ($body -and $body.since) { [string]$body.since } else { $null }
            $perCat = if ($body -and $body.perCat) { [int]$body.perCat } else { 100 }
            $sinceD = Convert-ToDate $sinceStr $true
            if ($script:IndexMode -eq 'everything') {
                $entries = Resolve-WatchConfig $cfg
                $res = @(Search-Everything $cfg $extMap $entries $kw $tp $sinceD 50000)
                $items = @()
                foreach ($x in $res) {
                    $items += [pscustomobject]@{
                        name = $x.Name
                        type = $x.Type
                        size = $x.Size
                        modified = $x.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                        path = $x.FullPath
                        category = Get-Category $cfg $x.FullPath
                    }
                }
                $q = Apply-CategoryQuota $items $cfg $perCat
                Send-Json $ctx ([pscustomobject]@{
                    ok = $true
                    total = $q.Total
                    categories = @($q.Categories)
                    results = @($q.Items)
                })
                return
            }
            $list = Load-Index (Get-IndexFile $cfg)
            $res = Invoke-Search $list $kw $tp $sinceD $null $null
            $items = @()
            foreach ($x in $res) {
                $items += [pscustomobject]@{
                    name = $x.Name
                    type = $x.Type
                    size = $x.Size
                    modified = $x.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    path = $x.FullPath
                    category = Get-Category $cfg $x.FullPath
                }
            }
            $q = Apply-CategoryQuota $items $cfg $perCat
            Send-Json $ctx ([pscustomobject]@{
                ok = $true
                total = $q.Total
                categories = @($q.Categories)
                results = @($q.Items)
            })
            return
        }
        catch {
            Send-Json $ctx ([pscustomobject]@{ ok = $false; error = $_.Exception.Message })
        }
        return
    }

    if ($path -eq '/api/monitor/start' -and $method -eq 'POST') {
        Start-Poller
        Send-Json $ctx ([pscustomobject]@{ ok = $true; monitor = Get-MonitorState })
        return
    }

    if ($path -eq '/api/monitor/stop' -and $method -eq 'POST') {
        Stop-Poller
        Send-Json $ctx ([pscustomobject]@{ ok = $true; monitor = Get-MonitorState })
        return
    }

    if ($path -eq '/api/open' -and $method -eq 'POST') {
        $body = Read-Body $ctx
        $target = if ($body) { [string]$body.path } else { '' }
        if ($target -and (Test-Path -LiteralPath $target)) {
            Start-Process -FilePath "explorer.exe" -ArgumentList "/select,`"$target`"" -ErrorAction SilentlyContinue
        }
        Send-Json $ctx ([pscustomobject]@{ ok = $true })
        return
    }

    if ($path -eq '/api/openfile' -and $method -eq 'POST') {
        $body = Read-Body $ctx
        $target = if ($body) { [string]$body.path } else { '' }
        $openExts = @('.mp4','.mkv','.mov','.avi','.ts','.flv','.webm','.m4v','.m2ts','.wmv','.mpg','.mpeg','.png','.jpg','.jpeg','.bmp','.webp','.gif','.tiff','.heic','.jfif','.mp3','.flac','.wav','.m4a','.aac','.ogg','.opus','.wma')
        $oe = [IO.Path]::GetExtension($target).ToLower()
        if ($target -and (Test-Path -LiteralPath $target -PathType Leaf) -and $openExts -contains $oe) {
            Start-Process -FilePath $target -ErrorAction SilentlyContinue
        }
        Send-Json $ctx ([pscustomobject]@{ ok = $true })
        return
    }

    if ($path -eq '/api/quit' -and $method -eq 'POST') {
        $script:StopRequested = $true
        Stop-LogMonitor
        Stop-Poller
        Send-Json $ctx ([pscustomobject]@{ ok = $true; message = "服务器正在退出" })
        if ($script:IndexMode -eq 'everything' -and $script:EsStartedByUs -and $cfg.stopEverythingOnExit) {
            try { [MFEs]::Exit() } catch {}
            Log "已随服务器关闭 Everything"
        }
        return
    }

    Send-Empty $ctx 404
}

$prefix = "http://localhost:$Port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
try {
    $listener.Start()
}
catch {
    $alive = $false
    try {
        $tc = New-Object System.Net.Sockets.TcpClient
        $async = $tc.BeginConnect('127.0.0.1', $Port, $null, $null)
        if ($async.AsyncWaitHandle.WaitOne(3000)) {
            $tc.EndConnect($async)
            $alive = $true
        }
        $tc.Close()
    }
    catch { $alive = $false }
    if ($alive) {
        Log "检测到已有 MediaFinder 服务器在运行 (端口 $Port), 直接打开浏览器"
        if (-not $NoBrowser) { Start-Process "http://localhost:$Port/" }
        exit 0
    }
    Log "启动失败: $($_.Exception.Message)"
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show("MediaFinder 启动失败:`n$($_.Exception.Message)`n`n端口 $Port 可能被其他程序占用。`n可编辑配置文件或用 -Port 参数指定其他端口。", "MediaFinder", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
    catch {}
    exit 1
}

Log "服务器启动, 监听 $prefix, 配置文件: $script:CfgPath"

Write-Host "======================================"
Write-Host "  MediaFinder 网页控制台"
Write-Host "  地址: $prefix"
Write-Host "  配置文件: $script:CfgPath"
Write-Host "  按 Ctrl+C 退出服务器"
Write-Host "======================================"

if (-not $NoBrowser) {
    Start-Process $prefix
}

$autoRefresh = $true
if ($null -ne $cfg.autoRefresh) { $autoRefresh = $cfg.autoRefresh }
if ($autoRefresh) { Start-Poller }

if ($script:IndexMode -eq 'everything') {
    try {
        $extMapI = Build-ExtMap $cfg
        [void](Sync-MediaLogs $cfg $extMapI $true)
    } catch {}
}
Start-LogMonitor

Ensure-Shortcut

try {
    while ($listener.IsListening -and -not $script:StopRequested) {
        try {
            $ctx = $listener.GetContext()
            Handle-Request $ctx
        }
        catch {
            Log "处理请求异常: $($_.Exception.Message)"
            try { $ctx.Response.Close() } catch {}
        }
    }
    Log "服务器已退出"
    Write-Host "服务器已退出"
}
finally {
    Stop-Poller
    $listener.Stop()
    $listener.Close()
}
