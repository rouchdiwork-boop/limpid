# Vérification complète du monorepo Limpid : formatage, analyse statique et
# tests, paquet par paquet.
#
#   powershell -File tool/check.ps1              # tous les paquets présents
#   powershell -File tool/check.ps1 limpid_core  # un seul paquet
#
# Ce script est l'équivalent PowerShell de tools/verify.sh, qui porte la même
# logique en bash. Les deux doivent rendre le même verdict sur le même dépôt.

$ErrorActionPreference = 'Continue'

# Windows PowerShell 5.1 écrit sur la console avec la page de code du
# terminal : sans cela, les accents du rapport sont illisibles.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $repoRoot

function Get-Members {
    param([string[]]$Names)

    $members = @()
    if ($Names.Count -gt 0) {
        foreach ($name in $Names) {
            foreach ($dir in @("packages/$name", "apps/$name")) {
                if (Test-Path "$dir/pubspec.yaml") { $members += $dir }
            }
        }
    }
    else {
        foreach ($dir in @(Get-ChildItem -Path 'packages', 'apps' -Directory -ErrorAction SilentlyContinue)) {
            if (Test-Path "$($dir.FullName)/pubspec.yaml") {
                $members += ($dir.FullName.Replace($repoRoot, '').TrimStart('\', '/'))
            }
        }
    }
    return $members
}

$members = Get-Members -Names $args

if ($members.Count -eq 0) {
    Write-Host "Aucun paquet trouvé dans packages/ ni apps/."
    exit 1
}

Write-Host "Paquets détectés : $($members.Count)"
foreach ($member in $members) { Write-Host "  • $member" }

$failed = $false
$totalTests = 0

foreach ($dir in $members) {
    $pkg = Split-Path -Leaf $dir
    Write-Host ''
    Write-Host "════════ $dir ════════"

    $pubspec = Get-Content "$dir/pubspec.yaml" -Raw
    $tool = if ($pubspec -match 'sdk:\s*flutter') { 'flutter' } else { 'dart' }
    Write-Host "• toolchain : $tool"

    if (-not (Test-Path "$dir/.dart_tool")) {
        Write-Host '• pub get'
        Push-Location $dir
        & $tool pub get | Out-Null
        Pop-Location
    }

    # `flutter analyze` ne génère pas les localisations : sans ce passage, une
    # machine neuve échoue sur `package:limpid_app/l10n/generated/...`.
    if ($tool -eq 'flutter' -and (Test-Path "$dir/l10n.yaml")) {
        Write-Host '• gen-l10n'
        Push-Location $dir
        & flutter gen-l10n | Out-Null
        Pop-Location
    }

    Write-Host '• format'
    Push-Location $dir
    $formatOut = & dart format --output=none --set-exit-if-changed . 2>&1 | Out-String
    $formatCode = $LASTEXITCODE
    Pop-Location
    if ($formatCode -eq 0) {
        Write-Host '  ✓ formaté'
    }
    else {
        Write-Host (($formatOut.Trim() -split "`n" | Select-Object -First 10) -join "`n")
        $failed = $true
    }

    Write-Host '• analyze'
    Push-Location $dir
    $analyzeOut = & $tool analyze --fatal-infos 2>&1 | Out-String
    Pop-Location
    if ($analyzeOut -match 'no issues found') {
        Write-Host '  ✓ 0 erreur, 0 avertissement'
    }
    else {
        Write-Host ($analyzeOut.Trim() -split "`n" | Select-Object -Last 20)
        $failed = $true
    }

    Write-Host '• test'
    if (Test-Path "$dir/test") {
        Push-Location $dir
        $testOut = & $tool test 2>&1 | Out-String
        Pop-Location
        $lastLine = ($testOut.Trim() -split "`n" | Select-Object -Last 1)
        Write-Host "  $lastLine"
        if ($testOut -match 'All tests passed') {
            $match = [regex]::Match($testOut, '\+(\d+):\s*All tests passed')
            if ($match.Success) { $totalTests += [int]$match.Groups[1].Value }
        }
        else {
            $failed = $true
        }
    }
    else {
        Write-Host '  (aucun dossier test/)'
    }
}

Write-Host ''
Write-Host '─────────────────────────────────────────'
Write-Host "Tests exécutés : $totalTests"
if (-not $failed) {
    Write-Host 'TOUT EST VERT'
    exit 0
}
else {
    Write-Host 'ÉCHEC — voir les sections ci-dessus'
    exit 1
}
