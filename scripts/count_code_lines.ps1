<#
.SYNOPSIS
    统计本项目 git 跟踪源码文件的有效代码行数。

.DESCRIPTION
    有效代码行 = 非空行 - 纯注释行（行注释 + 跨行块注释）。行尾注释仍按代码行计。
    文件清单取自 `git ls-files`，因此 build/、Release/、.gradle/ 等未跟踪产物天然不进统计。
    third_party/ 是 vendored 上游，docs/ 是文档，默认排除；需要时用 -Exclude '' 关闭。

.PARAMETER Root
    仓库内任意目录，默认当前目录（脚本会自动定位到 git 仓库根）。

.PARAMETER Exclude
    相对仓库根的路径前缀，默认排除上游与文档目录。传空数组表示不排除。

.PARAMETER Language
    只看指定语言，例如 -Language Java,XML。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\count_code_lines.ps1

.EXAMPLE
    .\scripts\count_code_lines.ps1 -Language Java -Exclude third_party/
#>
[CmdletBinding()]
param(
    [string]$Root = (Get-Location).Path,
    [string[]]$Exclude = @('third_party', 'docs', 'Release', 'build', 'node_modules', '.git'),
    [string[]]$Language
)

$ErrorActionPreference = 'Stop'

# 扩展名 -> 语言: 显示名, 行注释前缀(可多个), 块注释开始, 块注释结束
$LANGUAGES = @{
    '.java'       = @('Java',            '//',       '/*',   '*/')
    '.kt'         = @('Kotlin',          '//',       '/*',   '*/')
    '.kts'        = @('Kotlin Script',   '//',       '/*',   '*/')
    '.gradle'     = @('Gradle',          '//',       '/*',   '*/')
    '.js'         = @('JavaScript',      '//',       '/*',   '*/')
    '.mjs'        = @('JavaScript',      '//',       '/*',   '*/')
    '.ts'         = @('TypeScript',      '//',       '/*',   '*/')
    '.c'          = @('C',               '//',       '/*',   '*/')
    '.h'          = @('C/C++ Header',    '//',       '/*',   '*/')
    '.cpp'        = @('C++',             '//',       '/*',   '*/')
    '.cc'         = @('C++',             '//',       '/*',   '*/')
    '.hpp'        = @('C++ Header',      '//',       '/*',   '*/')
    '.cs'         = @('C#',              '//',       '/*',   '*/')
    '.php'        = @('PHP',             '//',       '/*',   '*/')
    '.css'        = @('CSS',             $null,      '/*',   '*/')
    '.sql'        = @('SQL',             '--',       '/*',   '*/')
    '.py'         = @('Python',          '#',        $null,  $null)
    '.sh'         = @('Shell',           '#',        $null,  $null)
    '.ps1'        = @('PowerShell',      '#',        '<#',   '#>')
    '.properties' = @('Properties',      '#',        $null,  $null)
    '.yml'        = @('YAML',            '#',        $null,  $null)
    '.yaml'       = @('YAML',            '#',        $null,  $null)
    '.toml'       = @('TOML',            '#',        $null,  $null)
    '.ass'        = @('ASS',             ';',        $null,  $null)
    '.xml'        = @('XML',             $null,      '<!--', '-->')
    '.html'       = @('HTML',            $null,      '<!--', '-->')
    '.htm'        = @('HTML',            $null,      '<!--', '-->')
    '.json'       = @('JSON',            $null,      $null,  $null)
}

function Get-LineKind {
    # 返回 'code' / 'comment'；块注释状态通过 $State 在行间保持
    param([string]$Line, [hashtable]$State, [string[]]$Spec)

    $rest = $Line
    while ($rest.Length -gt 0) {
        if ($State.InBlock) {
            if (-not $Spec[3]) { return 'comment' }
            $i = $rest.IndexOf($Spec[3], [StringComparison]::Ordinal)
            if ($i -lt 0) { return 'comment' }
            $rest = $rest.Substring($i + $Spec[3].Length).Trim()
            $State.InBlock = $false
            continue
        }
        if ($Spec[2] -and $rest.StartsWith($Spec[2], [StringComparison]::Ordinal)) {
            $State.InBlock = $true
            continue
        }
        if ($Spec[1]) {
            foreach ($mark in ($Spec[1] -split '\|')) {
                if ($rest.StartsWith($mark, [StringComparison]::Ordinal)) { return 'comment' }
            }
        }
        return 'code'
    }
    return 'comment'
}

$repoRoot = "$(& git -C $Root rev-parse --show-toplevel 2>$null)".Trim()
if ($LASTEXITCODE -ne 0 -or -not $repoRoot) { throw "不是 git 仓库: $Root" }

# 命令行传入 -Language Java,XML 时 PowerShell 不会自动拆成数组，这里统一按逗号再拆一次。
function Split-List {
    param([string[]]$Values)
    return @($Values | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
$Language = Split-List $Language
$Exclude = Split-List $Exclude

$prefixes = @($Exclude | ForEach-Object { $_.Replace('\', '/').Trim('/') })

function Test-Excluded {
    param([string]$Path)
    foreach ($p in $prefixes) {
        if ($Path -eq $p -or $Path.StartsWith("$p/", [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

$stats = @{}
$skipped = 0
$files = & git -C $repoRoot ls-files
if ($LASTEXITCODE -ne 0) { throw "git ls-files 失败" }

foreach ($rel in $files) {
    if (-not $rel) { continue }
    if (Test-Excluded $rel) { $skipped++; continue }
    $ext = [System.IO.Path]::GetExtension($rel).ToLowerInvariant()
    if (-not $LANGUAGES.ContainsKey($ext)) { $skipped++; continue }
    $spec = $LANGUAGES[$ext]
    $langName = $spec[0]
    if ($Language -and ($Language -notcontains $langName)) { continue }

    $full = Join-Path $repoRoot $rel
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }

    if (-not $stats.ContainsKey($langName)) {
        $stats[$langName] = [pscustomobject]@{ Language = $langName; Files = 0; Total = 0; Code = 0; Comment = 0; Blank = 0 }
    }
    $s = $stats[$langName]
    $s.Files++

    $state = @{ InBlock = $false }
    foreach ($raw in [System.IO.File]::ReadLines($full)) {
        $s.Total++
        $line = $raw.Trim()
        if ($line.Length -eq 0) { $s.Blank++; continue }
        if ((Get-LineKind $line $state $spec) -eq 'code') { $s.Code++ } else { $s.Comment++ }
    }
}

if ($stats.Count -eq 0) { Write-Host '没有匹配到任何源码文件。'; exit 0 }

$rows = @($stats.Values | Sort-Object -Property @{ Expression = 'Code'; Descending = $true })
$sumFiles = ($rows | Measure-Object Files -Sum).Sum
$sumTotal = ($rows | Measure-Object Total -Sum).Sum
$sumCode = ($rows | Measure-Object Code -Sum).Sum
$sumComment = ($rows | Measure-Object Comment -Sum).Sum
$sumBlank = ($rows | Measure-Object Blank -Sum).Sum

$branch = "$(& git -C $repoRoot rev-parse --abbrev-ref HEAD)".Trim()
$head = "$(& git -C $repoRoot rev-parse --short HEAD)".Trim()

Write-Host ''
Write-Host "项目有效代码行数统计  $repoRoot"
Write-Host ("分支 {0} @ {1}   统计时间 {2}" -f $branch, $head, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
if ($prefixes.Count -gt 0) {
    Write-Host ("已排除路径前缀: {0}（非源码/未匹配文件 {1} 个）" -f ($prefixes -join ', '), $skipped)
}
Write-Host ''

$rows |
    ForEach-Object {
        $share = '-'
        if ($sumCode -gt 0) { $share = '{0:P1}' -f ($_.Code / $sumCode) }
        [pscustomobject]@{
            语言     = $_.Language
            文件数   = $_.Files
            总行数   = $_.Total
            有效代码 = $_.Code
            注释行   = $_.Comment
            空行     = $_.Blank
            代码占比 = $share
        }
    } | Format-Table -AutoSize

Write-Host ("合计: {0} 个文件 / 总行 {1} / 有效代码 {2} / 注释 {3} / 空行 {4} / 代码占总行 {5:P1}" -f `
        $sumFiles, $sumTotal, $sumCode, $sumComment, $sumBlank, ($sumCode / $sumTotal))
