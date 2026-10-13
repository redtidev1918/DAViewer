# Android candidate 3d62b45 startup failure

2026-10-12: user reports the incident phone stuck at restoring login. Home and
settings cannot be entered. Candidate acceptance FAIL; ten-start acceptance
paused. PR #96 remains Draft, no merge/formal release. Original Incident
Verified remains PENDING. No new phone log has yet identified the awaited stage.

## Confirmed source defects and limits

`authRedirect(unknown, /splash, startupReady:true)` returns `/`, but the same
policy for `/` returned `/splash`. This is a routing cycle after startup timeout;
the old routing tests covered only its first half. The repair keeps public Home,
login and settings/diagnostics reachable while identity remains unknown.

Splash previously awaited OAuth and Cookie stages with separate 12-second
timeouts. Cookie restoration waits on accountLoad and its native mutation queue;
accountLoad calls official whoami and does not await Cookie restoration. There
is no confirmed source cycle between those operations. A native unfinished
Future or phone-specific failure remains to identify from new logs.

One independent 12-second overall timer now releases startup readiness. Finally
also releases it on completion/exception; release is once only. Readiness means
UI availability, not verified login. A root-provider-owned single-flight bootstrap
continues late restore after Splash unmount. No timeout deletes credentials,
clears native Cookies, or changes OAuth identity. Late identity refresh still
uses the existing account/epoch guards and router listeners.

AppLogger initialization flush occurs before runApp; seeing the Flutter restoring
screen means that initialization completed in this run. OAuth logging doesn't
await file flush. The independent disk-failure tests found and repaired close
error propagation/singleton retention; do not call it the device startup cause.

Release diagnostics record startup stage begin/complete/failure, ready reason,
OAuth status and route decisions without OAuth query parameters or Cookie data.
The old 3d62b45 APK cannot contain these new diagnostics.

## Windows ADB collection without settings access

Enable Android USB debugging, authorize this Windows computer, connect USB.
Use an explicit device serial from the first command. These commands don't clear
logcat, uninstall, log out or modify app data. Raw system logcat may contain
private values: retain locally and redact before sharing/committing.

```powershell
$adb = 'D:\Android\Sdk\platform-tools\adb.exe'
& $adb devices -l
$serial = 'REPLACE_WITH_PHONE_SERIAL'
& $adb -s $serial logcat -d -v threadtime > "$env:USERPROFILE\Desktop\DAViewer-startup-existing.txt"
& $adb -s $serial logcat -v threadtime > "$env:USERPROFILE\Desktop\DAViewer-startup-live.txt"
```

Keep live capture running, force-stop DAViewer from Android settings, then launch
it manually. Once stuck, Ctrl+C stops collection. Capture existing logs before
force-stop. Optional separate PowerShell window:

```powershell
& $adb -s $serial shell am force-stop app.daviewer
& $adb -s $serial shell monkey -p app.daviewer -c android.intent.category.LAUNCHER 1
& $adb -s $serial shell dumpsys activity activities > "$env:USERPROFILE\Desktop\DAViewer-startup-activity.txt"
```

A stock signed release usually blocks `run-as`/private-file pulls. Do not suggest
clearing data or uninstalling to work around inaccessible logs. On the replacement
candidate, verify first that Home/settings opens, then export the complete recent
20-launch archive from Settings → logs/diagnostics → top export button. Stop on
the first failure; OAuth/login and retained-account cold starts remain separate
acceptance scenarios. Only proceed with ten starts after the first paths succeed.

## Automated evidence

`startup_gate_test.dart`: never-completing bootstrap, simulated circular wait,
exception, successful completion; real Splash deadline, readiness listener and
GoRouter policy; Home/diagnostics reachable with OAuth unknown; late completion
does not issue readiness twice. `auth_routing_test.dart` checks every public
recovery route after deadline. Phone acceptance and native stall attribution
remain pending regardless of synthetic tests.
