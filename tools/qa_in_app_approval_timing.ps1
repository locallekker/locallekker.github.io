param(
  [string]$OutputDir = "qa_reports"
)

$ErrorActionPreference = "Stop"

function Read-RequiredInput {
  param(
    [string]$Prompt
  )

  while ($true) {
    $value = Read-Host $Prompt
    if (-not [string]::IsNullOrWhiteSpace($value)) {
      return $value.Trim()
    }
    Write-Host "Value is required." -ForegroundColor Yellow
  }
}

function Read-ScenarioResult {
  param(
    [string]$Id,
    [string]$Title,
    [string]$Expected,
    [string]$MetricPrompt
  )

  Write-Host ""
  Write-Host "=== ${Id}: $Title ===" -ForegroundColor Cyan
  Write-Host "Expected: $Expected"
  Write-Host "When done, enter result." -ForegroundColor DarkGray

  $result = ""
  while ($result -notin @("P", "F", "S")) {
    $result = (Read-Host "Result (P=Pass, F=Fail, S=Skip)").Trim().ToUpper()
  }

  $metric = Read-Host $MetricPrompt
  $notes = Read-Host "Notes"

  [PSCustomObject]@{
    Id = $Id
    Title = $Title
    Result = $result
    Metric = $metric
    Notes = $notes
  }
}

Write-Host "In-App Approval Timing QA Recorder" -ForegroundColor Green
Write-Host "This script records outcomes for the end-to-end approval timing checks." -ForegroundColor DarkGray

$tester = Read-RequiredInput "Tester name"
$build = Read-RequiredInput "Build/version"
$memberUserId = Read-RequiredInput "Member user_id"
$tpUserId = Read-RequiredInput "Trusted partner user_id"
$dealName = Read-RequiredInput "Deal name"

$scenarios = @()
$scenarios += Read-ScenarioResult -Id "A" -Title "Foreground immediate popup (in_app)" -Expected "Popup appears quickly after TP approval without sign-out/sign-in" -MetricPrompt "Popup delay in seconds"
$scenarios += Read-ScenarioResult -Id "B" -Title "Background then resume recovery (in_app)" -Expected "Resume triggers re-subscribe/fallback and popup appears" -MetricPrompt "Popup delay after resume in seconds"
$scenarios += Read-ScenarioResult -Id "C" -Title "Realtime interruption fallback (in_app)" -Expected "After reconnect, popup appears without re-login" -MetricPrompt "Recovery path (Stream/Fallback/Both)"
$scenarios += Read-ScenarioResult -Id "D" -Title "No duplicate popup" -Expected "Single approval does not repeatedly reprompt" -MetricPrompt "Duplicate popup count"
$scenarios += Read-ScenarioResult -Id "E" -Title "POS regression" -Expected "POS flow remains store-pay plus TP confirmation plus receipt generation" -MetricPrompt "Receipt observed? (Yes/No)"

$passCount = ($scenarios | Where-Object { $_.Result -eq "P" }).Count
$failCount = ($scenarios | Where-Object { $_.Result -eq "F" }).Count
$skipCount = ($scenarios | Where-Object { $_.Result -eq "S" }).Count

$finalVerdict = if ($failCount -eq 0 -and $skipCount -eq 0 -and $passCount -eq 5) { "PASS" } else { "FAIL" }

if (-not (Test-Path $OutputDir)) {
  New-Item -Path $OutputDir -ItemType Directory | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportPath = Join-Path $OutputDir "in_app_approval_timing_report_$timestamp.md"

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# In-App Approval Timing QA Report")
$lines.Add("")
$lines.Add("- Date: $(Get-Date -Format \"yyyy-MM-dd HH:mm:ss\")")
$lines.Add("- Tester: $tester")
$lines.Add("- Build: $build")
$lines.Add("- Member user_id: $memberUserId")
$lines.Add("- Trusted partner user_id: $tpUserId")
$lines.Add("- Deal: $dealName")
$lines.Add("")
$lines.Add("## Summary")
$lines.Add("")
$lines.Add("- Pass: $passCount")
$lines.Add("- Fail: $failCount")
$lines.Add("- Skip: $skipCount")
$lines.Add("- Final verdict: $finalVerdict")
$lines.Add("")
$lines.Add("## Scenario Results")
$lines.Add("")

foreach ($s in $scenarios) {
  $label = switch ($s.Result) {
    "P" { "Pass" }
    "F" { "Fail" }
    default { "Skip" }
  }

  $lines.Add("### Scenario $($s.Id): $($s.Title)")
  $lines.Add("")
  $lines.Add("- Result: $label")
  $lines.Add("- Metric: $($s.Metric)")
  $lines.Add("- Notes: $($s.Notes)")
  $lines.Add("")
}

$lines.Add("## Signoff")
$lines.Add("")
$lines.Add("- Tester: $tester")
$lines.Add("- Final verdict: $finalVerdict")

Set-Content -Path $reportPath -Value $lines -Encoding UTF8

Write-Host ""
Write-Host "Report written:" -ForegroundColor Green
Write-Host $reportPath -ForegroundColor Green

if ($finalVerdict -eq "PASS") {
  Write-Host "All scenarios passed." -ForegroundColor Green
} else {
  Write-Host "One or more scenarios failed or were skipped." -ForegroundColor Yellow
}
