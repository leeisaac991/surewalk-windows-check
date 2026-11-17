// SURE Walk - Windows laptop check, Windows Script Host part (JScript, runs with the built-in cscript).
// Fallback for when PowerShell is restricted: uses WMI and the registry to see the Bluetooth hardware,
// whether the iPhone is paired, whether Windows sees its message service, and the code-blocking policies.
// Cannot open the phone connection itself (only PowerShell / the compiled program can).
// Usage: cscript //nologo //E:JScript check-fallback.js <log file>
var logPath = WScript.Arguments.length > 0 ? WScript.Arguments(0) : 'surewalk-check-log.txt';
var fso = new ActiveXObject('Scripting.FileSystemObject');
function write(line) {
  try { var f = fso.OpenTextFile(logPath, 8, true); f.WriteLine(line); f.Close(); } catch (e) {}
}
function res(k, s, d) { write('RESULT ' + k + ' ' + s + ' ' + d); WScript.Echo('  [' + s + '] ' + k + ' ' + d); }
function info(t) { write('  ' + t); WScript.Echo('  ' + t); }

res('js-script', 'PASS', 'Windows Script Host runs');

var wmi = null;
try { wmi = GetObject('winmgmts:{impersonationLevel=impersonate}!\\\\.\\root\\cimv2'); } catch (e) { res('js-wmi', 'WARN', 'WMI not readable: ' + e.message); }

if (wmi) {
  try {
    var radios = new Enumerator(wmi.ExecQuery("SELECT Name, Status, ConfigManagerErrorCode FROM Win32_PnPEntity WHERE PNPClass = 'Bluetooth' AND (Name LIKE '%Radio%' OR Name LIKE '%Adapter%' OR Name LIKE '%Wireless Bluetooth%' OR Name LIKE '%Bluetooth(R)%')"));
    var nRadio = 0, okRadio = false;
    for (; !radios.atEnd(); radios.moveNext()) {
      var r = radios.item(); nRadio++;
      info('Bluetooth hardware: ' + r.Name + ' (' + r.Status + ')');
      if (r.ConfigManagerErrorCode == 0) okRadio = true;
    }
    if (!nRadio) res('js-bt-hardware', 'WARN', 'no Bluetooth adapter listed (may still exist under another name)');
    else res('js-bt-hardware', okRadio ? 'PASS' : 'WARN', okRadio ? 'Bluetooth adapter present and working' : 'Bluetooth adapter present but disabled or has a driver problem');
  } catch (e) { res('js-bt-hardware', 'WARN', e.message); }

  try {
    // Each paired device's services show up as BTHENUM\{service uuid}_... entries.
    var ents = new Enumerator(wmi.ExecQuery("SELECT Name, DeviceID FROM Win32_PnPEntity WHERE DeviceID LIKE 'BTHENUM%'"));
    var devs = {}, mas = false;
    for (; !ents.atEnd(); ents.moveNext()) {
      var en = ents.item(), id = String(en.DeviceID).toUpperCase();
      if (id.indexOf('{00001132-') >= 0) mas = true;
      if (id.indexOf('BTHENUM\\DEV_') == 0) devs[en.Name] = 1;
    }
    var names = []; for (var n in devs) names.push(n);
    info('paired Bluetooth devices: ' + (names.length ? names.join(', ') : 'none'));
    var phone = false;
    for (var i = 0; i < names.length; i++) if (/iphone/i.test(names[i])) phone = true;
    res('js-phone-paired', phone ? 'PASS' : 'WARN', phone ? 'an iPhone is paired' : 'no device named iPhone is paired');
    res('js-phone-map-listed', mas ? 'PASS' : 'WARN', mas ? 'Windows has seen a phone offer the message service' : 'Windows has not seen a message service yet (normal until the phone has connected once)');
  } catch (e) { res('js-phone-paired', 'WARN', e.message); }

  try {
    var svc = new Enumerator(wmi.ExecQuery("SELECT State FROM Win32_Service WHERE Name = 'bthserv'"));
    if (!svc.atEnd()) res('js-bt-service', svc.item().State == 'Running' ? 'PASS' : 'WARN', 'Bluetooth Support Service: ' + svc.item().State);
  } catch (e) {}
}

try {
  var dg = GetObject('winmgmts:\\\\.\\root\\Microsoft\\Windows\\DeviceGuard');
  var d = new Enumerator(dg.ExecQuery('SELECT UsermodeCodeIntegrityPolicyEnforcementStatus FROM Win32_DeviceGuard'));
  if (!d.atEnd()) {
    var st = d.item().UsermodeCodeIntegrityPolicyEnforcementStatus;
    res('js-wdac', st == 2 ? 'WARN' : 'PASS', 'App Control for apps: ' + (st == 2 ? 'ENFORCED' : st == 1 ? 'audit only' : 'off'));
  }
} catch (e) { info('App Control status: not readable'); }

var sh = new ActiveXObject('WScript.Shell');
function reg(k) { try { return sh.RegRead(k); } catch (e) { return null; } }
var srp = reg('HKLM\\SOFTWARE\\Policies\\Microsoft\\Windows\\Safer\\CodeIdentifiers\\DefaultLevel');
info('Software Restriction Policies: ' + (srp === null ? 'none' : 'DefaultLevel=' + srp));
var appid = reg('HKLM\\SYSTEM\\CurrentControlSet\\Services\\AppIDSvc\\Start');
if (appid !== null) info('AppLocker service start type: ' + appid + ' (2 = automatic, i.e. AppLocker likely active)');

try {
  var x = new ActiveXObject('MSXML2.XMLHTTP.6.0');   // uses the Windows / browser proxy settings
  x.open('HEAD', 'https://api.groupme.com/', false); x.send();
  res('js-net-groupme', 'PASS', 'GroupMe reachable through the Windows proxy settings (HTTP ' + x.status + ')');
} catch (e) { res('js-net-groupme', 'WARN', 'GroupMe not reachable: ' + e.message); }
