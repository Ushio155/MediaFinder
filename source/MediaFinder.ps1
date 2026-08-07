[CmdletBinding()]
param(
    [string]$Config = "",
    [switch]$Scan,
    [switch]$Monitor,
    [switch]$Menu,
    [string]$Search = "",
    [string]$Type = "",
    [string]$Since = "",
    [string]$From = "",
    [string]$To = "",
    [int]$Top = 30,
    [switch]$Open,
    [switch]$Copy
)

. (Join-Path $PSScriptRoot 'MediaFinder.Core.ps1')

$script:Top = $Top

function Read-Input($prompt) {
    if ([Console]::IsInputRedirected) {
        $line = [Console]::In.ReadLine()
        if ($null -eq $line) { return $null }
        return $line.TrimEnd("`r","`n")
    }
    return Read-Host $prompt
}

function Show-Results($res, $limit, $interactive, $cfg) {
    if ($null -eq $res -or $res.Count -eq 0) { Write-Host "未找到匹配文件"; return }
    $disp = @($res | Select-Object -First $limit)
    $groups = [ordered]@{}
    foreach ($x in $disp) {
        $cat = Get-Category $cfg $x.FullPath
        if (-not $cat) { $cat = '其他' }
        if (-not $groups.Contains($cat)) { $groups[$cat] = @() }
        $groups[$cat] += $x
    }
    $i = 0
    foreach ($cat in $groups.Keys) {
        Write-Host ""
        Write-Host "──── $cat  ($($groups[$cat].Count) 个) ────"
        foreach ($x in $groups[$cat]) {
            $i++
            $mb = [math]::Round($x.Size / 1MB, 1)
            Write-Host ("{0,3}. [{1}] {2}   {3} MB   {4}" -f $i, $x.Type, $x.Name, $mb, $x.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
            Write-Host ("        {0}" -f $x.FullPath)
        }
    }
    Write-Host ""
    Write-Host ("共 {0} 条 (显示前 {1} 条)" -f $res.Count, $disp.Count)
    if ($interactive) {
        $sel = Read-Input "输入序号:打开所在文件夹 | 序号O:打开文件 | 序号C:复制路径 | 回车跳过"
        if ($sel) {
            $n = 0
            if ([int]::TryParse(($sel -replace '[A-Za-zOoCc]',''), [ref]$n)) {
                if ($n -ge 1 -and $n -le $disp.Count) {
                    $f = $disp[$n - 1].FullPath
                    if ($sel -match 'O') { Start-Process -FilePath $f }
                    elseif ($sel -match 'C') { Set-Clipboard $f; Write-Host "已复制: $f" }
                    else {
                        $dir = Split-Path -Parent $f
                        if (Test-Path -LiteralPath $dir) { Start-Process -FilePath $dir }
                    }
                }
            }
        }
    }
}

function Start-Monitor($cfg, $extMap) {
    $idxPath = Get-IndexFile $cfg
    $list = Load-Index $idxPath
    if ($list.Count -eq 0) { Write-Host "索引为空, 建议先运行 -Scan 建立初始索引" }
    $entries = Resolve-WatchConfig $cfg
    $watchers = @()
    $sources = @()
    $wn = 0
    foreach ($e in $entries) {
        $p = $e.Path
        if (-not (Test-Path -LiteralPath $p)) { Write-Host "跳过不存在: $p"; continue }
        $wn++
        $w = New-Object System.IO.FileSystemWatcher
        $w.Path = $p
        $w.IncludeSubdirectories = $true
        $w.NotifyFilter = [IO.NotifyFilters]'FileName,LastWrite,CreationTime'
        $w.EnableRaisingEvents = $true
        $watchers += $w
        foreach ($evt in 'Created','Renamed') {
            $src = "MF_W${wn}_$evt"
            $sources += $src
            Register-ObjectEvent -InputObject $w -EventName $evt -SourceIdentifier $src | Out-Null
        }
        Write-Host "监控中: $p"
    }
    if ($watchers.Count -eq 0) { Write-Host "没有可监控的目录, 退出"; return }
    Write-Host "实时监控运行中, Ctrl+C 退出..."
    try {
        while ($true) {
            $handled = $false
            foreach ($src in $sources) {
                $pending = @(Get-Event -SourceIdentifier $src -ErrorAction SilentlyContinue)
                if ($pending.Count -gt 0) {
                    foreach ($e2 in $pending) {
                        if ($e2.SourceEventArgs.FullPath) {
                            Add-IndexEntry $list $e2.SourceEventArgs.FullPath $extMap $entries
                            $handled = $true
                        }
                    }
                    Remove-Event -SourceIdentifier $src -ErrorAction SilentlyContinue
                }
            }
            if ($handled) { Save-Index $idxPath $list; Write-Host "已更新索引" }
            Start-Sleep -Milliseconds 800
        }
    }
    finally {
        foreach ($w in $watchers) { $w.Dispose() }
    }
}

function Show-Menu($cfg, $extMap) {
    $idxPath = Get-IndexFile $cfg
    while ($true) {
        Write-Host ""
        Write-Host "==== 媒体文件快速查找工具 ===="
        Write-Host "  1. 扫描并建立索引"
        Write-Host "  2. 启动实时监控 (Ctrl+C 停止)"
        Write-Host "  3. 搜索文件"
        Write-Host "  4. 查看/编辑配置"
        Write-Host "  0. 退出"
        $c = Read-Input "请选择"
        if ($null -eq $c) { return }
        switch ($c) {
            '1' { Invoke-FullScan $cfg $extMap }
            '2' { Start-Monitor $cfg $extMap }
            '3' {
                $kw = Read-Input "关键字(留空=全部)"
                if ($null -eq $kw) { return }
                $tp = Read-Input "类型 video/image/audio (留空=全部)"
                if ($null -eq $tp) { return }
                $sn = Read-Input "时间 如 7d/24h/30m (留空=全部)"
                if ($null -eq $sn) { return }
                $sinceD = Convert-ToDate $sn $true
                $list = Load-Index $idxPath
                $res = Invoke-Search $list $kw $tp $sinceD $null $null
                Show-Results $res $script:Top $true $cfg
            }
            '4' {
                Write-Host "监控目录:"
                $i = 0
                foreach ($e in (Resolve-WatchConfig $cfg)) { $i++; Write-Host "  $i. $($e.Path)" }
                if ($cfg.autoDetect -ne $false) { Write-Host "  (已开启自动识别常见目录)" }
                Write-Host "配置文件: $script:CfgPath"
                Write-Host "编辑后重新运行脚本即生效"
            }
            '0' { return }
        }
    }
}

$cfg = Get-Config $Config
$extMap = Build-ExtMap $cfg

$searchRequested = $false
foreach ($k in 'Search','Type','Since','From','To') {
    if ($PSBoundParameters.ContainsKey($k)) { $searchRequested = $true }
}

if ($Monitor) { Start-Monitor $cfg $extMap; exit }
if ($Scan) { Invoke-FullScan $cfg $extMap; exit }
if ($searchRequested) {
    $list = Load-Index (Get-IndexFile $cfg)
    $sinceD = Convert-ToDate $Since $true
    $fromD = Convert-ToDate $From $false
    $toD = Convert-ToDate $To $false
    $res = Invoke-Search $list $Search $Type $sinceD $fromD $toD
    if ($Open) { if ($res.Count -gt 0) { $d = Split-Path -Parent $res[0].FullPath; if (Test-Path -LiteralPath $d) { Start-Process -FilePath $d } }; exit }
    if ($Copy) { if ($res.Count -gt 0) { Set-Clipboard $res[0].FullPath; Write-Host "已复制: $($res[0].FullPath)" }; exit }
    Show-Results $res $Top $false $cfg
    exit
}
Show-Menu $cfg $extMap
