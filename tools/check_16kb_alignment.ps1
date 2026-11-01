Add-Type -AssemblyName System.IO.Compression.FileSystem

# Verifies every 64-bit native library in the AAB has p_align >= 16384 (Play 16 KB requirement).
$aab = Resolve-Path "build\app\outputs\bundle\release\app-release.aab"
$zip = [IO.Compression.ZipFile]::OpenRead($aab)
$libs = $zip.Entries | Where-Object { $_.FullName -match '^base/lib/(arm64-v8a|x86_64)/.*\.so$' }

$fail = $false
foreach ($lib in $libs) {
    $ms = New-Object IO.MemoryStream
    $s = $lib.Open(); $s.CopyTo($ms); $s.Close()
    $b = $ms.ToArray(); $ms.Dispose()

    $phoff = [BitConverter]::ToInt64($b, 0x20)
    $phentsize = [BitConverter]::ToUInt16($b, 0x36)
    $phnum = [BitConverter]::ToUInt16($b, 0x38)

    $min = [uint64]::MaxValue
    for ($i = 0; $i -lt $phnum; $i++) {
        $off = $phoff + ($i * $phentsize)
        if ([BitConverter]::ToUInt32($b, $off) -ne 1) { continue }   # PT_LOAD only
        $align = [BitConverter]::ToUInt64($b, $off + 0x30)
        if ($align -lt $min) { $min = $align }
    }

    if ($min -eq [uint64]::MaxValue) { continue }
    $ok = $min -ge 16384
    if (-not $ok) { $fail = $true }
    $status = if ($ok) { "OK " } else { "BAD" }
    Write-Host ("  [{0}] p_align=0x{1}  {2}" -f $status, $min.ToString('X'), $lib.FullName)
}
$zip.Dispose()

Write-Host ""
if ($fail) {
    Write-Host "16 KB ALIGNMENT: FAILED" -ForegroundColor Red
}
else {
    Write-Host "16 KB ALIGNMENT: PASSED (all 64-bit PT_LOAD segments >= 0x4000)" -ForegroundColor Green
}
