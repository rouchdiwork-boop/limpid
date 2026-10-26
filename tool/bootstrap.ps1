# Installation des dépendances de tous les paquets du monorepo Limpid.
#
#   powershell -File tool/bootstrap.ps1              # tous les paquets présents
#   powershell -File tool/bootstrap.ps1 limpid_core  # un seul paquet
#
# Équivalent de `melos bootstrap` pour les environnements où melos n'est pas
# installé. Ce script est l'équivalent PowerShell de tool/bootstrap.sh.

$ErrorActionPreference = 'Continue'

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $repoRoot

$members = @()
if ($args.Count -gt 0) {
    foreach ($name in $args) {
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

if ($members.Count -eq 0) {
    Write-Host "Aucun paquet trouvé dans packages/ ni apps/."
    exit 0
}

$failed = $false

foreach ($dir in $members) {
    $pkg = Split-Path -Leaf $dir
    $pubspec = Get-Content "$dir/pubspec.yaml" -Raw
    $tool = if ($pubspec -match 'sdk:\s*flutter') { 'flutter' } else { 'dart' }

    Write-Host "→ $pkg ($tool pub get)"
    Push-Location $dir
    & $tool pub get
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ! échec de $tool pub get pour $pkg"
        $failed = $true
    }
    Pop-Location
}

Write-Host ''
if (-not $failed) {
    Write-Host 'Dépendances installées.'
    exit 0
}
else {
    Write-Host 'ÉCHEC — certaines dépendances n''ont pas pu être installées.'
    exit 1
}
