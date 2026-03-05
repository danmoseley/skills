# Validates description sizes across all plugins.
# Usage: pwsh eng/validate-descriptions.ps1 [-MaxSkillDescription 1024] [-MaxPluginAggregate 15000]

param(
    [int]$MaxSkillDescription = 1024,
    [int]$MaxPluginAggregate = 15000,
    [string]$PluginsDir = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $PluginsDir) {
    $RepoRoot = Split-Path $PSScriptRoot -Parent
    $PluginsDir = Join-Path $RepoRoot 'plugins'
}

function Get-SkillDescription([string]$FilePath) {
    $content = Get-Content $FilePath -Raw
    if ($content -notmatch '(?ms)^---\r?\n(.*?)\r?\n^---\s*$') {
        return $null
    }
    $yaml = $Matches[1]

    # Use powershell-yaml if available for accurate parsing
    if (Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue) {
        $parsed = ConvertFrom-Yaml $yaml
        if ($parsed -and $parsed.ContainsKey('description')) {
            return [string]$parsed['description']
        }
        return $null
    }

    # Fallback: regex-based extraction
    # Block scalar (description: >- or description: > or description: | etc.)
    if ($yaml -match '(?sm)^description:\s*[>|]-?\s*\r?\n((?:[ \t]+.*(?:\r?\n|$))*)') {
        $lines = $Matches[1] -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        return ($lines -join ' ')
    }
    # Double-quoted
    if ($yaml -match 'description:\s*"((?:[^"\\]|\\.)*)"') {
        return $Matches[1]
    }
    # Single-quoted
    if ($yaml -match "description:\s*'([^']*)'") {
        return $Matches[1]
    }
    # Simple unquoted single-line
    if ($yaml -match '(?m)^description:\s+(.+)$') {
        return $Matches[1].Trim()
    }
    return $null
}

Write-Host '=== Description Size Validation ===' -ForegroundColor Cyan
Write-Host ''

$pluginDirs = Get-ChildItem -Path $PluginsDir -Directory
$violations = @()
$results = @()

foreach ($plugin in $pluginDirs) {
    $skillsDir = Join-Path $plugin.FullName 'skills'
    if (-not (Test-Path $skillsDir)) { continue }

    $skillDirs = Get-ChildItem -Path $skillsDir -Directory |
        Where-Object { $_.Name -ne 'shared' }

    $totalChars = 0
    $maxSkillChars = 0
    $skillCount = 0

    foreach ($skill in $skillDirs) {
        $skillFile = Join-Path $skill.FullName 'SKILL.md'
        if (-not (Test-Path $skillFile)) { continue }

        $desc = Get-SkillDescription $skillFile
        if ($null -eq $desc) { continue }

        $len = $desc.Length
        $skillCount++
        $totalChars += $len
        if ($len -gt $maxSkillChars) { $maxSkillChars = $len }

        if ($len -gt $MaxSkillDescription) {
            $violations += [PSCustomObject]@{
                Plugin = $plugin.Name
                Skill  = $skill.Name
                Chars  = $len
                Type   = 'per-skill'
                Limit  = $MaxSkillDescription
            }
        }
    }

    if ($totalChars -gt $MaxPluginAggregate) {
        $violations += [PSCustomObject]@{
            Plugin = $plugin.Name
            Skill  = '(aggregate)'
            Chars  = $totalChars
            Type   = 'aggregate'
            Limit  = $MaxPluginAggregate
        }
    }

    $pass = @($violations | Where-Object { $_.Plugin -eq $plugin.Name }).Count -eq 0
    $results += [PSCustomObject]@{
        Plugin    = $plugin.Name
        Skills    = $skillCount
        Total     = $totalChars
        MaxSkill  = $maxSkillChars
        Status    = if ($pass) { [char]0x2705 + ' PASS' } else { [char]0x274C + ' FAIL' }
    }
}

# Print summary table
$fmt = '{0,-24} {1,6} {2,13} {3,11} {4}'
Write-Host ($fmt -f 'Plugin', 'Skills', 'Total Chars', 'Max Skill', 'Status')
Write-Host ([string]::new([char]0x2500, 65))

foreach ($r in $results) {
    Write-Host ($fmt -f $r.Plugin, $r.Skills, $r.Total.ToString('N0'), $r.MaxSkill.ToString('N0'), $r.Status)
}

Write-Host ''
Write-Host "Limits: per-skill max $($MaxSkillDescription.ToString('N0')) chars, per-plugin max $($MaxPluginAggregate.ToString('N0')) chars"

# Print individual violations
if ($violations.Count -gt 0) {
    Write-Host ''
    foreach ($v in $violations) {
        if ($v.Type -eq 'per-skill') {
            Write-Host "$([char]0x274C) $($v.Plugin)/$($v.Skill): Description too long ($($v.Chars) chars, max $($v.Limit))" -ForegroundColor Red
        } else {
            Write-Host "$([char]0x274C) $($v.Plugin): Aggregate description too long ($($v.Chars) chars, max $($v.Limit))" -ForegroundColor Red
        }
    }
    Write-Host "`n$($violations.Count) violation(s) found." -ForegroundColor Red
    exit 1
} else {
    Write-Host "$([char]0x2705) All plugins pass description size limits." -ForegroundColor Green
    exit 0
}
