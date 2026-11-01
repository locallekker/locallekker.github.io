$ErrorActionPreference = 'Stop'

# Reads the Supabase CLI access token out of Windows Credential Manager.
Add-Type -Namespace Cred -Name Native -MemberDefinition @'
[DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
public static extern bool CredRead(string target, int type, int flags, out IntPtr credential);
[DllImport("advapi32.dll")]
public static extern void CredFree(IntPtr cred);
'@

function Get-SupabaseToken {
    $ptr = [IntPtr]::Zero
    if (-not [Cred.Native]::CredRead('Supabase CLI:supabase', 1, 0, [ref]$ptr)) {
        throw "Could not read Supabase CLI credential"
    }
    # x64 CREDENTIAL layout: CredentialBlobSize @32, CredentialBlob ptr @40.
    $size = [Runtime.InteropServices.Marshal]::ReadInt32($ptr, 32)
    $blob = [Runtime.InteropServices.Marshal]::ReadIntPtr($ptr, 40)
    $bytes = New-Object byte[] $size
    [Runtime.InteropServices.Marshal]::Copy($blob, $bytes, 0, $size)
    [Cred.Native]::CredFree($ptr)
    $tok = [Text.Encoding]::UTF8.GetString($bytes)
    if ($tok -match "`0") { $tok = [Text.Encoding]::Unicode.GetString($bytes) }
    return $tok.Trim()
}

function Invoke-SupabaseSql {
    param([string]$Sql, [string]$ProjectRef = 'qdrotavcmmevhgveodcp')
    $tok = Get-SupabaseToken
    $esc = $Sql.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n')
    $body = '{"query":"' + $esc + '"}'
    Invoke-RestMethod -Method Post `
        -Uri "https://api.supabase.com/v1/projects/$ProjectRef/database/query" `
        -Headers @{ Authorization = "Bearer $tok"; 'Content-Type' = 'application/json' } `
        -Body $body
}
