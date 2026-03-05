# Tests for eng/validate-descriptions.ps1
# Run: pwsh eng/tests/validate-descriptions.tests.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptPath = Join-Path $PSScriptRoot '..' 'validate-descriptions.ps1'
$passed = 0
$failed = 0

function New-TestFixture {
    param(
        [hashtable[]]$Plugins
    )
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "desc-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    foreach ($plugin in $Plugins) {
        foreach ($skill in $plugin.Skills) {
            $skillDir = Join-Path $root $plugin.Name 'skills' $skill.Name
            New-Item -Path $skillDir -ItemType Directory -Force | Out-Null
            # Escape description for YAML double-quoted scalar
            $escapedDesc = $skill.Description -replace '\\', '\\'
            $escapedDesc = $escapedDesc -replace '"', '\"'
            $escapedDesc = $escapedDesc -replace "`r?`n", '\n'
            $content = "---`nname: $($skill.Name)`ndescription: `"$escapedDesc`"`n---`n# $($skill.Name)`nContent."
            [System.IO.File]::WriteAllText((Join-Path $skillDir 'SKILL.md'), $content)
        }
    }
    return $root
}

function Assert-ExitCode {
    param([string]$TestName, [int]$Expected, [int]$Actual)
    if ($Expected -eq $Actual) {
        $script:passed++
        Write-Host "  ✅ $TestName" -ForegroundColor Green
    } else {
        $script:failed++
        Write-Host "  ❌ $TestName (expected exit $Expected, got $Actual)" -ForegroundColor Red
    }
}

Write-Host '=== validate-descriptions.ps1 tests ===' -ForegroundColor Cyan
Write-Host ''

# Test 1: All descriptions under limits → exit 0
$fixture = New-TestFixture -Plugins @(
    @{ Name = 'test-plugin'; Skills = @(
        @{ Name = 'skill-a'; Description = ('a' * 500) },
        @{ Name = 'skill-b'; Description = ('b' * 400) }
    )}
)
& pwsh $ScriptPath -PluginsDir $fixture -MaxSkillDescription 1024 -MaxPluginAggregate 15000 > $null 2>&1
Assert-ExitCode 'Under both limits passes' 0 $LASTEXITCODE
Remove-Item $fixture -Recurse -Force

# Test 2: Single skill over per-skill limit → exit 1
$fixture = New-TestFixture -Plugins @(
    @{ Name = 'test-plugin'; Skills = @(
        @{ Name = 'skill-ok'; Description = ('a' * 500) },
        @{ Name = 'skill-big'; Description = ('b' * 1025) }
    )}
)
& pwsh $ScriptPath -PluginsDir $fixture -MaxSkillDescription 1024 -MaxPluginAggregate 15000 > $null 2>&1
Assert-ExitCode 'Per-skill violation fails' 1 $LASTEXITCODE
Remove-Item $fixture -Recurse -Force

# Test 3: Skill at exactly the limit → exit 0
$fixture = New-TestFixture -Plugins @(
    @{ Name = 'test-plugin'; Skills = @(
        @{ Name = 'skill-exact'; Description = ('x' * 1024) }
    )}
)
& pwsh $ScriptPath -PluginsDir $fixture -MaxSkillDescription 1024 -MaxPluginAggregate 15000 > $null 2>&1
Assert-ExitCode 'Exactly at per-skill limit passes' 0 $LASTEXITCODE
Remove-Item $fixture -Recurse -Force

# Test 4: Aggregate over plugin limit → exit 1
$fixture = New-TestFixture -Plugins @(
    @{ Name = 'test-plugin'; Skills = @(
        @{ Name = 'skill-1'; Description = ('a' * 800) },
        @{ Name = 'skill-2'; Description = ('b' * 800) },
        @{ Name = 'skill-3'; Description = ('c' * 800) }
    )}
)
& pwsh $ScriptPath -PluginsDir $fixture -MaxSkillDescription 1024 -MaxPluginAggregate 2000 > $null 2>&1
Assert-ExitCode 'Per-plugin aggregate violation fails' 1 $LASTEXITCODE
Remove-Item $fixture -Recurse -Force

# Test 5: Aggregate exactly at limit → exit 0
$fixture = New-TestFixture -Plugins @(
    @{ Name = 'test-plugin'; Skills = @(
        @{ Name = 'skill-1'; Description = ('a' * 500) },
        @{ Name = 'skill-2'; Description = ('b' * 500) }
    )}
)
& pwsh $ScriptPath -PluginsDir $fixture -MaxSkillDescription 1024 -MaxPluginAggregate 1000 > $null 2>&1
Assert-ExitCode 'Exactly at aggregate limit passes' 0 $LASTEXITCODE
Remove-Item $fixture -Recurse -Force

# Test 6: Multiple plugins, only one violates → exit 1
$fixture = New-TestFixture -Plugins @(
    @{ Name = 'good-plugin'; Skills = @(
        @{ Name = 'skill-a'; Description = ('a' * 100) }
    )},
    @{ Name = 'bad-plugin'; Skills = @(
        @{ Name = 'skill-b'; Description = ('b' * 2000) }
    )}
)
& pwsh $ScriptPath -PluginsDir $fixture -MaxSkillDescription 1024 -MaxPluginAggregate 15000 > $null 2>&1
Assert-ExitCode 'One bad plugin among good ones fails' 1 $LASTEXITCODE
Remove-Item $fixture -Recurse -Force

Write-Host ''
Write-Host "Results: $passed passed, $failed failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
if ($failed -gt 0) { exit 1 }
