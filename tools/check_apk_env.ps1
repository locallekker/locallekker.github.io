Add-Type -AssemblyName System.IO.Compression.FileSystem

$apk = Resolve-Path "build\app\outputs\flutter-apk\app-release.apk"
$zip = [IO.Compression.ZipFile]::OpenRead($apk)

Write-Host "--- bundled .env (values masked) ---"
$entry = $zip.Entries | Where-Object { $_.FullName -like "*flutter_assets/.env" } | Select-Object -First 1
if ($entry) {
    $reader = New-Object IO.StreamReader($entry.Open())
    $txt = $reader.ReadToEnd()
    $reader.Close()
    foreach ($line in ($txt -split "`n")) {
        if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
        $parts = $line -split '=', 2
        $k = $parts[0].Trim()
        $v = $parts[1].Trim()
        if ($v.Length -gt 10) { $v = $v.Substring(0, 6) + "...(len $($v.Length))" }
        Write-Host "  $k = $v"
    }
    Write-Host ""
    if ($txt -match 'sk_live_|SERVICE_ROLE') {
        Write-Host "SECRET SCAN: !! SECRET FOUND !!" -ForegroundColor Red
    }
    else {
        Write-Host "SECRET SCAN: clean (no sk_live_ / SERVICE_ROLE)" -ForegroundColor Green
    }
}
else {
    Write-Host "  no .env asset found in APK"
}
$zip.Dispose()
