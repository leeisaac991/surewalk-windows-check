# SURE Walk - Windows laptop check, PowerShell part (bridge option A).
# Run by RUN-CHECK.cmd. Installs nothing, changes no settings, sends no texts.
# Reads only the NUMBER of messages in the iPhone inbox (never their text) to prove the phone link works.
param(
  [string]$Log = (Join-Path $PSScriptRoot 'surewalk-check-log.txt'),
  [string]$Work = (Join-Path $env:LOCALAPPDATA 'surewalk-check'),
  [string]$Mode = 'phone',
  [string]$Device = ''
)
$ErrorActionPreference = 'Stop'

function Res([string]$key, [string]$status, [string]$detail) {
  Add-Content -Path $Log -Value "RESULT $key $status $detail"
  Write-Host "  [$status] $key $detail"
}
function Info([string]$text) {
  Add-Content -Path $Log -Value "  $text"
  Write-Host "  $text"
}
function Msg($err) {
  $x = $err
  if ($x -is [System.Management.Automation.ErrorRecord]) { $x = $x.Exception }
  while ($x.InnerException) { $x = $x.InnerException }
  return $x.Message
}

Res 'ps-script' 'PASS' "check-windows.ps1 runs (PowerShell $($PSVersionTable.PSVersion))"
$lm = $ExecutionContext.SessionState.LanguageMode
Info "language mode: $lm"
try { Get-ExecutionPolicy -List | ForEach-Object { Info ("execution policy " + $_.Scope + " = " + $_.ExecutionPolicy) } } catch {}

# ------------------------------------------------------------ security policies (read only)
Add-Content -Path $Log -Value ''; Add-Content -Path $Log -Value '----- Policies (PowerShell) -----'
try {
  $x = [xml](Get-AppLockerPolicy -Effective -Xml)
  $cols = @($x.AppLockerPolicy.RuleCollection)
  if ($cols.Count -eq 0 -or -not $cols[0]) { Res 'applocker' 'PASS' 'no AppLocker rules' }
  else {
    $enforced = @()
    foreach ($c in $cols) {
      Info ("AppLocker " + $c.Type + ": " + $c.EnforcementMode + ", " + @($c.ChildNodes).Count + " rules")
      if ($c.EnforcementMode -eq 'Enabled') { $enforced += $c.Type }
    }
    if ($enforced.Count) { Res 'applocker' 'WARN' ("enforced for: " + ($enforced -join ', ') + " - the RESULT lines for programs/scripts show what actually got through") }
    else { Res 'applocker' 'PASS' 'rules exist but none enforced' }
  }
} catch { Info ("AppLocker: could not read (" + (Msg $_) + ") - fine on Home editions") }
try {
  $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard
  $um = [int]$dg.UsermodeCodeIntegrityPolicyEnforcementStatus
  $names = @('off', 'audit only', 'ENFORCED')
  if ($um -eq 2) { Res 'wdac' 'WARN' 'App Control (WDAC) enforced for apps - unsigned programs/scripts may be blocked' }
  else { Res 'wdac' 'PASS' ("App Control for apps: " + $names[$um]) }
} catch { Info ("App Control status: could not read (" + (Msg $_) + ")") }
try {
  $srp = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers' -ErrorAction Stop
  if ($null -ne $srp.DefaultLevel) { Info ("Software Restriction Policies present, DefaultLevel=" + $srp.DefaultLevel) } else { Info 'Software Restriction Policies: key present, no rules set' }
} catch { Info 'Software Restriction Policies: none' }
try {
  $bt = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Bluetooth' -ErrorAction Stop
  $bt.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { Info ("Bluetooth policy " + $_.Name + " = " + $_.Value) }
} catch { Info 'Bluetooth policy: none set by IT' }

$pl = Get-Process -Name 'PhoneExperienceHost', 'PhoneLink', 'YourPhone' -ErrorAction SilentlyContinue
if ($pl) { Res 'phone-link' 'WARN' 'Phone Link is running - if it is linked to the iPhone, unlink it (the iPhone may allow only one message reader)' }
else { Res 'phone-link' 'PASS' 'Phone Link not running' }

if ($lm -ne 'FullLanguage') {
  Res 'ps-full' 'FAIL' "PowerShell is in $lm - the bridge cannot be a PowerShell script here (option B / Node may still work)"
  exit 0
}

# ------------------------------------------------------------ local server port + network
Add-Content -Path $Log -Value ''; Add-Content -Path $Log -Value '----- Local port and network (PowerShell) -----'
try {
  $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
  $l.Start(); $port = $l.LocalEndpoint.Port
  $c = New-Object System.Net.Sockets.TcpClient; $c.Connect('127.0.0.1', $port); $c.Close(); $l.Stop()
  Res 'ps-loopback' 'PASS' 'a local-only server port can be opened without admin'
} catch { Res 'ps-loopback' 'FAIL' (Msg $_) }
try {
  $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 8787); $l.Start(); $l.Stop()
  Res 'ps-port-8787' 'PASS' 'port 8787 (dashboard) is free'
} catch { Res 'ps-port-8787' 'WARN' 'port 8787 is in use - the server can use another port' }

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
try { $px = [System.Net.WebRequest]::GetSystemWebProxy().GetProxy('https://api.groupme.com/'); if ($px.Host -ne 'api.groupme.com') { Info ("Windows proxy for GroupMe: " + $px) } } catch {}
foreach ($h in 'api.groupme.com', 'cdn.jsdelivr.net', 'nodejs.org') {
  try {
    $r = Invoke-WebRequest -Uri "https://$h/" -UseBasicParsing -Method Head -TimeoutSec 12
    Res "ps-net-$h" 'PASS' ("reachable, HTTP " + [int]$r.StatusCode)
  } catch {
    if ($_.Exception.Response) { Res "ps-net-$h" 'PASS' ("reachable, HTTP " + [int]$_.Exception.Response.StatusCode) }
    else { Res "ps-net-$h" 'WARN' (Msg $_) }
  }
}

# ------------------------------------------------------------ Bluetooth via Windows' own APIs
Add-Content -Path $Log -Value ''; Add-Content -Path $Log -Value '----- Bluetooth (PowerShell) -----'
try {
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  $ext = [System.WindowsRuntimeSystemExtensions].GetMethods()
  $script:AsTaskOp = $ext | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
  $script:AsTaskAct = $ext | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' } | Select-Object -First 1
} catch { Res 'ps-winrt' 'FAIL' ("cannot load the Windows Runtime bridge: " + (Msg $_)); exit 0 }

function T([string]$name) {
  foreach ($a in 'Windows.Foundation', 'Windows.Devices', 'Windows.System.Devices', 'Windows.Networking', 'Windows.Storage') {
    $t = [Type]::GetType("$name, $a, ContentType=WindowsRuntime")
    if ($t) { return $t }
  }
  throw "cannot load Windows type $name"
}
function Await($op, [Type]$type, [int]$ms = 15000) {
  $task = $script:AsTaskOp.MakeGenericMethod($type).Invoke($null, @($op))
  if (-not $task.Wait($ms)) { throw ("timed out after " + ($ms / 1000) + " s") }
  return $task.Result
}
function AwaitAction($op, [int]$ms = 15000) {
  $task = $script:AsTaskAct.Invoke($null, @($op))
  if (-not $task.Wait($ms)) { throw ("timed out after " + ($ms / 1000) + " s") }
}

try {
  $Radio = T 'Windows.Devices.Radios.Radio'
  $list = Await ($Radio::GetRadiosAsync()) ([System.Collections.Generic.IReadOnlyList``1].MakeGenericType($Radio))
  $btr = @($list | Where-Object { "$($_.Kind)" -eq 'Bluetooth' })
  if (-not $btr.Count) { Res 'ps-bt-radio' 'FAIL' 'no Bluetooth radio found'; exit 0 }
  if ("$($btr[0].State)" -eq 'On') { Res 'ps-bt-radio' 'PASS' 'Bluetooth is on' }
  else { Res 'ps-bt-radio' 'FAIL' ("Bluetooth is " + $btr[0].State + " - turn it on and run again"); exit 0 }
  $Adapter = T 'Windows.Devices.Bluetooth.BluetoothAdapter'
  $ad = Await ($Adapter::GetDefaultAsync()) $Adapter
  if ($ad) { Info ("adapter: classic=" + $ad.IsClassicSupported + ", LE=" + $ad.IsLowEnergySupported) }
  if ($ad -and -not $ad.IsClassicSupported) { Res 'ps-bt-classic' 'FAIL' 'adapter has no classic Bluetooth - the iPhone message link needs it'; exit 0 }
  Res 'ps-winrt' 'PASS' 'Windows Bluetooth APIs usable from PowerShell'
} catch { Res 'ps-winrt' 'FAIL' (Msg $_); exit 0 }

$BtDev = T 'Windows.Devices.Bluetooth.BluetoothDevice'
$DevInfo = T 'Windows.Devices.Enumeration.DeviceInformation'
$phones = @()
try {
  $sel = $BtDev::GetDeviceSelectorFromPairingState($true)
  $coll = Await ($DevInfo::FindAllAsync($sel)) (T 'Windows.Devices.Enumeration.DeviceInformationCollection')
  Info ("paired Bluetooth devices: " + @($coll).Count)
  foreach ($di in $coll) {
    $d = Await ($BtDev::FromIdAsync($di.Id)) $BtDev
    if (-not $d) { continue }
    $major = "$($d.ClassOfDevice.MajorClass)"
    Info ("  " + $d.Name + " (" + $major + ")")
    $isPhone = ($major -eq 'Phone') -or ($d.Name -match 'iPhone')
    if ($Device) { $isPhone = $d.Name -like "*$Device*" }
    if ($isPhone) { $phones += $d }
  }
} catch { Res 'ps-paired' 'FAIL' (Msg $_); exit 0 }
if (-not $phones.Count) { Res 'ps-phone-found' 'FAIL' 'no paired phone - pair the iPhone in Settings > Bluetooth & devices, then run again'; exit 0 }
Res 'ps-phone-found' 'PASS' ("paired phone: " + (($phones | ForEach-Object { $_.Name }) -join ', '))
if ($Mode -eq 'nophone') { Info 'nophone: skipping the connection to the phone'; exit 0 }

# ------------------------------------------------------------ MAP (Message Access) test, read-only
$Cache = T 'Windows.Devices.Bluetooth.BluetoothCacheMode'
$SvcId = T 'Windows.Devices.Bluetooth.Rfcomm.RfcommServiceId'
$Sock = T 'Windows.Networking.Sockets.StreamSocket'
$Prot = T 'Windows.Networking.Sockets.SocketProtectionLevel'
$DW = T 'Windows.Storage.Streams.DataWriter'
$DR = T 'Windows.Storage.Streams.DataReader'
$MAS_UUID = [byte[]](0xbb, 0x58, 0x2b, 0x40, 0x42, 0x0c, 0x11, 0xdb, 0xb0, 0xde, 0x08, 0x00, 0x20, 0x0c, 0x9a, 0x66)
$Codes = @{ 0xA0 = 'OK'; 0x90 = 'Continue'; 0xC0 = 'Bad Request'; 0xC1 = 'Unauthorized'; 0xC3 = 'Forbidden'; 0xC4 = 'Not Found'; 0xC6 = 'Not Acceptable'; 0xD0 = 'Internal Error'; 0xD1 = 'Not Implemented'; 0xD3 = 'Service Unavailable' }
function CodeName([int]$c) { $n = $Codes[$c]; if (-not $n) { $n = 'unknown' }; return ('0x{0:X2} {1}' -f $c, $n) }

function Add16([System.Collections.Generic.List[byte]]$b, [int]$n) { $b.Add([byte](($n -shr 8) -band 0xFF)); $b.Add([byte]($n -band 0xFF)) }
function AddBytesHdr([System.Collections.Generic.List[byte]]$b, [int]$id, [byte[]]$v) { $b.Add([byte]$id); Add16 $b ($v.Length + 3); $b.AddRange($v) }
function AddName([System.Collections.Generic.List[byte]]$b, [string]$name) {
  $u = New-Object System.Collections.Generic.List[byte]
  if ($name.Length) { $u.AddRange([System.Text.Encoding]::BigEndianUnicode.GetBytes($name)); $u.Add(0); $u.Add(0) }
  AddBytesHdr $b 0x01 $u.ToArray()
}
function AddConn([System.Collections.Generic.List[byte]]$b, [byte[]]$cid) { if ($cid) { $b.Add(0xCB); $b.AddRange($cid) } }
function Xfer([int]$op, [System.Collections.Generic.List[byte]]$body) {
  $p = New-Object System.Collections.Generic.List[byte]
  $p.Add([byte]$op); Add16 $p ($body.Count + 3); $p.AddRange($body)
  $script:w.WriteBytes($p.ToArray())
  $null = Await ($script:w.StoreAsync()) ([uint32]) 10000
  $got = Await ($script:r.LoadAsync(3)) ([uint32]) 20000
  if ($got -lt 3) { throw 'the phone closed the connection' }
  $code = $script:r.ReadByte(); $len = ([int]$script:r.ReadByte() -shl 8) -bor $script:r.ReadByte()
  $all = New-Object byte[] $len
  $all[0] = $code; $all[1] = [byte](($len -shr 8) -band 0xFF); $all[2] = [byte]($len -band 0xFF)
  if ($len -gt 3) { $null = Await ($script:r.LoadAsync([uint32]($len - 3))) ([uint32]) 20000; for ($i = 3; $i -lt $len; $i++) { $all[$i] = $script:r.ReadByte() } }
  return , $all
}
function Headers([byte[]]$p, [int]$off) {
  $h = @{}; $i = $off
  while ($i -lt $p.Length) {
    $id = [int]$p[$i]; $kind = $id -band 0xC0
    if ($kind -eq 0x00 -or $kind -eq 0x40) {
      $n = ([int]$p[$i + 1] -shl 8) -bor $p[$i + 2]
      if ($n -lt 3) { break }
      $h[$id] = [byte[]]$p[($i + 3)..($i + $n - 1)]; if ($n -eq 3) { $h[$id] = [byte[]]@() }
      $i += $n
    } elseif ($kind -eq 0x80) { $h[$id] = [byte[]]@($p[$i + 1]); $i += 2 }
    else { $h[$id] = [byte[]]$p[($i + 1)..($i + 4)]; $i += 5 }
  }
  return $h
}

$anyOk = $false
foreach ($phone in $phones) {
  $name = $phone.Name
  try {
    $all = Await ($phone.GetRfcommServicesAsync($Cache::Uncached)) (T 'Windows.Devices.Bluetooth.Rfcomm.RfcommDeviceServicesResult') 30000
    $ids = @($all.Services | ForEach-Object { $_.ServiceId.Uuid.ToString().Substring(4, 4) }) | Sort-Object -Unique
    Info ("$name offers services (short ids): " + ($ids -join ' ') + "  [1132 = messages, 112f = contacts, 111f = calls]")
    $res = Await ($phone.GetRfcommServicesForIdAsync($SvcId::FromShortId(0x1132), $Cache::Uncached)) (T 'Windows.Devices.Bluetooth.Rfcomm.RfcommDeviceServicesResult') 30000
    if (-not $res.Services -or $res.Services.Count -eq 0) {
      Res 'ps-phone-map' 'FAIL' ("$name does not offer the message service right now (" + $res.Error + ") - unlock it, keep it near, and on the iPhone: Settings > Bluetooth > (i) next to this laptop > Show Notifications ON")
      continue
    }
    $svc = $res.Services[0]
    $script:sock = [Activator]::CreateInstance($Sock)
    AwaitAction ($script:sock.ConnectAsync($svc.ConnectionHostName, $svc.ConnectionServiceName, $Prot::BluetoothEncryptionAllowNullAuthentication)) 30000
    Res 'ps-phone-rfcomm' 'PASS' "connected to the message service on $name"
    # PowerShell's own overload matching cannot pass Windows stream objects to these constructors; reflection can.
    $script:w = $DW.GetConstructor([Type[]]@((T 'Windows.Storage.Streams.IOutputStream'))).Invoke(@($script:sock.OutputStream))
    $script:r = $DR.GetConstructor([Type[]]@((T 'Windows.Storage.Streams.IInputStream'))).Invoke(@($script:sock.InputStream))

    $b = New-Object System.Collections.Generic.List[byte]
    $b.AddRange([byte[]](0x10, 0x00, 0x20, 0x00)); AddBytesHdr $b 0x46 $MAS_UUID
    $resp = Xfer 0x80 $b
    if ($resp[0] -ne 0xA0) { Res 'ps-phone-map' 'FAIL' ("$name refused the message session: " + (CodeName $resp[0]) + " - on the iPhone turn Show Notifications ON for this laptop and accept any prompt"); $script:sock.Dispose(); continue }
    $cid = (Headers $resp 7)[0xCB]

    foreach ($dir in '', 'telecom', 'msg') {
      $b = New-Object System.Collections.Generic.List[byte]
      $b.AddRange([byte[]](0x02, 0x00)); AddConn $b $cid; AddName $b $dir
      $resp = Xfer 0x85 $b
      if ($resp[0] -ne 0xA0) { throw ("could not open folder '" + $dir + "': " + (CodeName $resp[0])) }
    }

    # GetMessagesListing of inbox with MaxListCount = 0: the phone returns only how many messages there are.
    $b = New-Object System.Collections.Generic.List[byte]
    AddConn $b $cid
    AddBytesHdr $b 0x42 ([System.Text.Encoding]::ASCII.GetBytes("x-bt/MAP-msg-listing`0"))
    AddName $b 'inbox'
    AddBytesHdr $b 0x4C ([byte[]](0x01, 0x02, 0x00, 0x00))
    $resp = Xfer 0x83 $b
    $size = $null; $guard = 0
    while ($true) {
      $h = Headers $resp 3
      if ($h.ContainsKey(0x4C)) {
        $ap = $h[0x4C]; $i = 0
        while ($i + 1 -lt $ap.Length) { $tag = $ap[$i]; $n = $ap[$i + 1]; if ($tag -eq 0x12 -and $n -eq 2) { $size = ([int]$ap[$i + 2] -shl 8) -bor $ap[$i + 3] }; $i += 2 + $n }
      }
      if ($resp[0] -ne 0x90 -or $guard++ -gt 50) { break }
      $b = New-Object System.Collections.Generic.List[byte]; AddConn $b $cid
      $resp = Xfer 0x83 $b
    }
    if ($resp[0] -eq 0xA0) {
      $sz = 'size not reported'; if ($null -ne $size) { $sz = "$size messages in inbox" }
      Res 'ps-phone-map' 'PASS' "$name lets this laptop read messages ($sz). Sending uses the same session."
      $anyOk = $true
    } else { Res 'ps-phone-map' 'FAIL' ("$name opened the session but refused the inbox listing: " + (CodeName $resp[0])) }

    $b = New-Object System.Collections.Generic.List[byte]; AddConn $b $cid
    try { $null = Xfer 0x81 $b } catch {}
    $script:sock.Dispose()
    if ($anyOk) { break }
  } catch {
    Res 'ps-phone-map' 'FAIL' ("$name - " + (Msg $_) + " (phone unlocked and nearby? Show Notifications ON for this laptop?)")
    try { $script:sock.Dispose() } catch {}
  }
}
exit 0
