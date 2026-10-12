[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$Serial,
    [string]$AdbPath = 'D:\Android\Sdk\platform-tools\adb.exe',
    [ValidateRange(1, 10)][int]$Count = 1,
    [ValidateRange(1, 60)][int]$ObserveSeconds = 30,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$packageName = 'app.daviewer'
if (-not (Test-Path -LiteralPath $AdbPath -PathType Leaf)) {
    throw 'ADB is missing; supply -AdbPath pointing to the installed adb.exe.'
}
if ([string]::IsNullOrWhiteSpace($Serial) -or $Serial.StartsWith('-')) {
    throw 'Supply the exact target device serial from adb devices -l.'
}
function Invoke-DeviceAdb([string[]]$DeviceArguments) {
    $result = & $AdbPath -s $Serial @DeviceArguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "ADB failed: $result" }
    return $result
}
$deviceState = Invoke-DeviceAdb -DeviceArguments @('get-state')
if (($deviceState -join '').Trim() -ne 'device') { throw 'Target device is not ready/authorized.' }
if ($WhatIfPreference) {
    for ($launchIndex = 1; $launchIndex -le $Count; $launchIndex++) {
        $null = $PSCmdlet.ShouldProcess($Serial, "Force-stop/start $packageName (launch $launchIndex)")
    }
    return
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path (Get-Location) ('.android-acceptance-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
}
$resolvedOutput = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $resolvedOutput) { throw 'Output directory exists; choose a new directory.' }
$null = New-Item -ItemType Directory -Path $resolvedOutput
$observations = [Collections.Generic.List[object]]::new()
for ($launchIndex = 1; $launchIndex -le $Count; $launchIndex++) {
    if (-not $PSCmdlet.ShouldProcess($Serial, "Force-stop/start $packageName (launch $launchIndex)")) { break }
    $startedAt = (Get-Date).ToString('o')
    $null = Invoke-DeviceAdb -DeviceArguments @('shell', 'am', 'force-stop', $packageName)
    # Resolve the declared launcher rather than inventing an activity class.
    $activity = Invoke-DeviceAdb -DeviceArguments @('shell', 'cmd', 'package', 'resolve-activity', '--brief', $packageName)
    $component = @($activity | Where-Object { $_ -match '^app\.daviewer/[^\s]+$' }) | Select-Object -Last 1
    if ([string]::IsNullOrWhiteSpace($component)) { throw 'DAViewer launcher could not be resolved.' }
    $null = Invoke-DeviceAdb -DeviceArguments @('shell', 'am', 'start', '-W', '-n', $component.Trim())
    Start-Sleep -Seconds $ObserveSeconds
    $outcome = (Read-Host "Launch $launchIndex : inspect personalized feed without login; PASS / FAIL / PENDING").Trim().ToUpperInvariant()
    if ($outcome -notin @('PASS', 'FAIL', 'PENDING')) { $outcome = 'PENDING' }
    $observations.Add([pscustomobject]@{ Launch = $launchIndex; StartedAt = $startedAt; Outcome = $outcome })
    $observations | Export-Csv -LiteralPath (Join-Path $resolvedOutput 'observations.csv') -NoTypeInformation -Encoding utf8
    if ($outcome -ne 'PASS') {
        Write-Host 'Stop here and export the app recent-launch archive immediately.'
        break
    }
}
Write-Host "Observations: $resolvedOutput"
Write-Host 'Export Settings > Logs and diagnostics > Export recent launch logs (20). Device acceptance still requires those logs.'
