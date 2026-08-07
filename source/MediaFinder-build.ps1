[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$outDir = Split-Path -Parent $dir
$csc = Get-ChildItem "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe", "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $csc) { Write-Host "未找到 csc.exe (.NET Framework 编译器)"; exit 1 }
$src = Join-Path $dir 'MediaFinder-launcher.cs'
if (-not (Test-Path -LiteralPath $src)) { Write-Host "缺少 MediaFinder-launcher.cs"; exit 1 }
$out = Join-Path $outDir 'MediaFinder.exe'

$args = New-Object System.Collections.ArrayList
[void]$args.Add('/nologo')
[void]$args.Add('/target:winexe')
[void]$args.Add('/r:System.Windows.Forms.dll')
[void]$args.Add('/r:Microsoft.CSharp.dll')
$ico = Join-Path $dir 'MediaFinder.ico'
if (Test-Path -LiteralPath $ico) { [void]$args.Add('/win32icon:' + $ico) }
[void]$args.Add('/out:' + $out)

$resFiles = @(
    'MediaFinder.Core.ps1', 'MediaFinder-thumb.ps1', 'MediaFinder.ps1', 'MediaFinderServer.ps1',
    'Everything.exe', 'Everything64.dll',
    'MediaFinder.cmd', 'MediaFinder-web.cmd', 'MediaFinder-web.vbs', 'MediaFinder-web-visible.cmd', 'MediaFinder-stop.cmd',
    'THIRD-PARTY.txt', 'MediaFinder-README.txt',
    'MediaFinder.config.json', 'MediaFinder.ico',
    'web\index.html', 'web\style.css', 'web\app.js'
)
foreach ($rf in $resFiles) {
    $rp = Join-Path $dir $rf
    if (Test-Path -LiteralPath $rp) {
        $name = 'MF.' + ($rf -replace '[\\/]', '.')
        [void]$args.Add('/resource:' + $rp + ',' + $name)
    }
    else { Write-Host "警告: 缺少资源 $rf" }
}
[void]$args.Add($src)

& $csc.FullName @args
if (Test-Path -LiteralPath $out) {
    Write-Host ""
    Write-Host "构建成功: $out ($((Get-Item -LiteralPath $out).Length) B)"
    Write-Host "把这个 MediaFinder.exe 单独发给别人，双击即可自动运行并在桌面生成快捷方式。"
}
else {
    Write-Host "构建失败"
    exit 1
}
