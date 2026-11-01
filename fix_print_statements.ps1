#!/usr/bin/env pwsh

# Script to replace print() statements with production-safe logging
# This script scans Dart files and replaces print() with conditional debug logging

Write-Host "🔍 Scanning for print() statements in production code..." -ForegroundColor Cyan

$libPath = "lib"
$excludedPaths = @("test", "REV_01")  # Don't modify test files or old revisions

# Count print statements
$printCount = 0
$dartFiles = Get-ChildItem -Path $libPath -Filter *.dart -Recurse | Where-Object {
    $exclude = $false
    foreach ($excludePath in $excludedPaths) {
        if ($_.FullName -like "*$excludePath*") {
            $exclude = $true
            break
        }
    }
    -not $exclude
}

foreach ($file in $dartFiles) {
    $content = Get-Content $file.FullName -Raw
    $regexMatches = [regex]::Matches($content, "print\(")
    $printCount += $regexMatches.Count
}

Write-Host "Found $printCount print() statements in production code" -ForegroundColor Yellow
Write-Host ""
Write-Host "⚠️  IMPORTANT: This script will:" -ForegroundColor Yellow
Write-Host "   1. Add 'import package:flutter/foundation.dart' if needed" -ForegroundColor Yellow
Write-Host "   2. Wrap ALL print() statements with if (kDebugMode)" -ForegroundColor Yellow
Write-Host "   3. Create backups of modified files" -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "Do you want to proceed? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Operation cancelled." -ForegroundColor Red
    exit
}

Write-Host ""
Write-Host "Processing files..." -ForegroundColor Cyan

$modifiedCount = 0
$backupDir = "print_statement_backups_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

foreach ($file in $dartFiles) {
    $content = Get-Content $file.FullName -Raw
    $originalContent = $content
    
    # Check if file has print statements
    if ($content -notmatch "print\(") {
        continue
    }
    
    # Create backup
    $relativePath = $file.FullName.Replace((Get-Location).Path, "").TrimStart('\', '/')
    $backupPath = Join-Path $backupDir $relativePath
    $backupFolder = Split-Path $backupPath -Parent
    if (-not (Test-Path $backupFolder)) {
        New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
    }
    Copy-Item $file.FullName $backupPath -Force
    
    # Add foundation import if not present
    if ($content -notmatch "import 'package:flutter/foundation\.dart'") {
        # Find the last import statement
        $lines = $content -split "`n"
        $lastImportIndex = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "^import ") {
                $lastImportIndex = $i
            }
        }
        
        if ($lastImportIndex -ge 0) {
            $lines = @($lines[0..$lastImportIndex]) + @("import 'package:flutter/foundation.dart';") + @($lines[($lastImportIndex + 1)..($lines.Count - 1)])
            $content = $lines -join "`n"
        }
    }
    
    # Replace print statements with conditional logging
    # Pattern: Find print(...) and wrap with if (kDebugMode)
    $pattern = '(\s*)print\(((?:[^()]|\((?:[^()]|\([^()]*\))*\))*)\);'
    
    $content = [regex]::Replace($content, $pattern, {
            param($match)
            $indent = $match.Groups[1].Value
        
            # Check if already wrapped in kDebugMode
            $beforeContext = $match.Value.Substring(0, [Math]::Max(0, $match.Index - 50))
            if ($beforeContext -match 'if\s*\(\s*kDebugMode\s*\)') {
                return $match.Value  # Already wrapped, skip
            }
        
            # Wrap in kDebugMode
            return "${indent}if (kDebugMode) {`n${indent}  print($($match.Groups[2].Value));`n${indent}}"
        })
    
    # Only save if content changed
    if ($content -ne $originalContent) {
        $content | Out-File -FilePath $file.FullName -Encoding UTF8 -NoNewline
        $modifiedCount++
        Write-Host "  ✓ Modified: $($file.Name)" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "✅ Processing complete!" -ForegroundColor Green
Write-Host "   Modified files: $modifiedCount" -ForegroundColor Cyan
Write-Host "   Backups saved to: $backupDir" -ForegroundColor Cyan
Write-Host ""
Write-Host "📋 Next steps:" -ForegroundColor Yellow
Write-Host "   1. Run 'flutter analyze' to check for issues"
Write-Host "   2. Test the app to ensure everything works"
Write-Host "   3. If issues occur, restore from backups in $backupDir"
