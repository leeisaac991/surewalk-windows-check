// SURE Walk - Windows laptop check, compiled-program part (bridge option B).
// RUN-CHECK.cmd builds this with the C# compiler that ships with Windows (.NET Framework 4) and runs it.
// It is for laptops where PowerShell is restricted but programs you build can still run.
// Same read-only phone test as check-windows.ps1: asks only HOW MANY messages are in the inbox, never their text.
// Usage: btcheck.exe <log file> [phone|nophone] [device name filter]
// Written for the old C# 5 compiler: no $"..." strings, no ?. operator.
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.Threading;
using Windows.Foundation;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.Rfcomm;
using Windows.Devices.Enumeration;
using Windows.Devices.Radios;
using Windows.Networking.Sockets;
using Windows.Storage.Streams;

class BtCheck
{
    static string LogPath;
    static DataWriter W;
    static DataReader R;
    static readonly byte[] MasUuid = { 0xbb, 0x58, 0x2b, 0x40, 0x42, 0x0c, 0x11, 0xdb, 0xb0, 0xde, 0x08, 0x00, 0x20, 0x0c, 0x9a, 0x66 };

    static void Res(string key, string status, string detail)
    {
        try { File.AppendAllText(LogPath, "RESULT " + key + " " + status + " " + detail + "\r\n"); } catch { }
        Console.WriteLine("  [" + status + "] " + key + " " + detail);
    }
    static void Info(string text)
    {
        try { File.AppendAllText(LogPath, "  " + text + "\r\n"); } catch { }
        Console.WriteLine("  " + text);
    }
    static string Msg(Exception e)
    {
        Exception x = e;
        while (x.InnerException != null) x = x.InnerException;
        return x.Message;
    }
    // Poll instead of AsTask(): AsTask lives in a library that needs the Windows SDK to compile against.
    static void Settle(IAsyncInfo op, int ms)
    {
        Stopwatch sw = Stopwatch.StartNew();
        while (op.Status == AsyncStatus.Started)
        {
            if (sw.ElapsedMilliseconds > ms) { try { op.Cancel(); } catch { } throw new TimeoutException("timed out after " + (ms / 1000) + " s"); }
            Thread.Sleep(15);
        }
        if (op.Status == AsyncStatus.Error) throw op.ErrorCode;
        if (op.Status == AsyncStatus.Canceled) throw new OperationCanceledException();
    }
    static T Wait<T>(IAsyncOperation<T> op, int ms) { Settle(op, ms); return op.GetResults(); }
    static void WaitA(IAsyncAction op, int ms) { Settle(op, ms); op.GetResults(); }
    static string Code(int c)
    {
        string n;
        switch (c)
        {
            case 0xA0: n = "OK"; break;
            case 0x90: n = "Continue"; break;
            case 0xC0: n = "Bad Request"; break;
            case 0xC1: n = "Unauthorized"; break;
            case 0xC3: n = "Forbidden"; break;
            case 0xC4: n = "Not Found"; break;
            case 0xC6: n = "Not Acceptable"; break;
            case 0xD0: n = "Internal Error"; break;
            case 0xD1: n = "Not Implemented"; break;
            case 0xD3: n = "Service Unavailable"; break;
            default: n = "unknown"; break;
        }
        return string.Format("0x{0:X2} {1}", c, n);
    }

    static void Add16(List<byte> b, int n) { b.Add((byte)((n >> 8) & 0xFF)); b.Add((byte)(n & 0xFF)); }
    static void AddHdr(List<byte> b, byte id, byte[] v) { b.Add(id); Add16(b, v.Length + 3); b.AddRange(v); }
    static void AddName(List<byte> b, string name)
    {
        List<byte> u = new List<byte>();
        if (name.Length > 0) { u.AddRange(Encoding.BigEndianUnicode.GetBytes(name)); u.Add(0); u.Add(0); }
        AddHdr(b, 0x01, u.ToArray());
    }
    static void AddConn(List<byte> b, byte[] cid) { if (cid != null) { b.Add(0xCB); b.AddRange(cid); } }

    static byte[] Xfer(byte op, List<byte> body)
    {
        List<byte> p = new List<byte>();
        p.Add(op); Add16(p, body.Count + 3); p.AddRange(body);
        W.WriteBytes(p.ToArray());
        Wait<uint>(W.StoreAsync(), 10000);
        uint got = Wait<uint>(R.LoadAsync(3), 20000);
        if (got < 3) throw new IOException("the phone closed the connection");
        byte code = R.ReadByte();
        int len = (R.ReadByte() << 8) | R.ReadByte();
        byte[] all = new byte[Math.Max(len, 3)];
        all[0] = code; all[1] = (byte)((len >> 8) & 0xFF); all[2] = (byte)(len & 0xFF);
        if (len > 3)
        {
            Wait<uint>(R.LoadAsync((uint)(len - 3)), 20000);
            for (int i = 3; i < len; i++) all[i] = R.ReadByte();
        }
        return all;
    }
    static Dictionary<int, byte[]> Headers(byte[] p, int off)
    {
        Dictionary<int, byte[]> h = new Dictionary<int, byte[]>();
        int i = off;
        while (i < p.Length)
        {
            int id = p[i], kind = id & 0xC0;
            if (kind == 0x00 || kind == 0x40)
            {
                if (i + 2 >= p.Length) break;
                int n = (p[i + 1] << 8) | p[i + 2];
                if (n < 3 || i + n > p.Length) break;
                byte[] v = new byte[n - 3]; Array.Copy(p, i + 3, v, 0, n - 3); h[id] = v; i += n;
            }
            else if (kind == 0x80) { if (i + 1 >= p.Length) break; h[id] = new byte[] { p[i + 1] }; i += 2; }
            else { if (i + 4 >= p.Length) break; byte[] v = new byte[4]; Array.Copy(p, i + 1, v, 0, 4); h[id] = v; i += 5; }
        }
        return h;
    }

    static int Main(string[] args)
    {
        LogPath = args.Length > 0 ? args[0] : "surewalk-check-log.txt";
        string mode = args.Length > 1 ? args[1] : "phone";
        string want = args.Length > 2 ? args[2] : "";
        Res("cs-exe-runs", "PASS", "a program built on this laptop runs from your own folder");

        try
        {
            IReadOnlyList<Radio> radios = Wait(Radio.GetRadiosAsync(), 15000);
            Radio bt = null;
            foreach (Radio r in radios) if (r.Kind == RadioKind.Bluetooth) { bt = r; break; }
            if (bt == null) { Res("cs-bt-radio", "FAIL", "no Bluetooth radio found"); return 0; }
            if (bt.State != RadioState.On) { Res("cs-bt-radio", "FAIL", "Bluetooth is " + bt.State + " - turn it on and run again"); return 0; }
            Res("cs-winrt", "PASS", "Windows Bluetooth APIs usable from a compiled program");
        }
        catch (Exception e) { Res("cs-winrt", "FAIL", Msg(e)); return 0; }

        List<BluetoothDevice> phones = new List<BluetoothDevice>();
        try
        {
            DeviceInformationCollection coll = Wait(DeviceInformation.FindAllAsync(BluetoothDevice.GetDeviceSelectorFromPairingState(true)), 15000);
            foreach (DeviceInformation di in coll)
            {
                BluetoothDevice d = Wait(BluetoothDevice.FromIdAsync(di.Id), 15000);
                if (d == null) continue;
                bool isPhone = d.ClassOfDevice.MajorClass == BluetoothMajorClass.Phone || d.Name.IndexOf("iPhone", StringComparison.OrdinalIgnoreCase) >= 0;
                if (want.Length > 0) isPhone = d.Name.IndexOf(want, StringComparison.OrdinalIgnoreCase) >= 0;
                if (isPhone) phones.Add(d);
            }
        }
        catch (Exception e) { Res("cs-paired", "FAIL", Msg(e)); return 0; }
        if (phones.Count == 0) { Res("cs-phone-found", "FAIL", "no paired phone - pair the iPhone in Settings > Bluetooth & devices, then run again"); return 0; }
        List<string> names = new List<string>();
        foreach (BluetoothDevice d in phones) names.Add(d.Name);
        Res("cs-phone-found", "PASS", "paired phone: " + string.Join(", ", names));
        if (mode == "nophone") { Info("skipping the phone connection (already tested, or nophone)"); return 0; }

        foreach (BluetoothDevice phone in phones)
        {
            StreamSocket sock = null;
            try
            {
                RfcommDeviceServicesResult res = Wait(phone.GetRfcommServicesForIdAsync(RfcommServiceId.FromShortId(0x1132), BluetoothCacheMode.Uncached), 30000);
                if (res.Services.Count == 0)
                {
                    Res("cs-phone-map", "FAIL", phone.Name + " does not offer the message service right now (" + res.Error + ") - unlock it, keep it near, Show Notifications ON for this laptop");
                    continue;
                }
                RfcommDeviceService svc = res.Services[0];
                sock = new StreamSocket();
                WaitA(sock.ConnectAsync(svc.ConnectionHostName, svc.ConnectionServiceName, SocketProtectionLevel.BluetoothEncryptionAllowNullAuthentication), 30000);
                Res("cs-phone-rfcomm", "PASS", "connected to the message service on " + phone.Name);
                W = new DataWriter(sock.OutputStream);
                R = new DataReader(sock.InputStream);

                List<byte> b = new List<byte>(new byte[] { 0x10, 0x00, 0x20, 0x00 });
                AddHdr(b, 0x46, MasUuid);
                byte[] resp = Xfer(0x80, b);
                if (resp[0] != 0xA0)
                {
                    Res("cs-phone-map", "FAIL", phone.Name + " refused the message session: " + Code(resp[0]) + " - turn Show Notifications ON for this laptop on the iPhone");
                    sock.Dispose(); continue;
                }
                byte[] cid = null;
                Headers(resp, 7).TryGetValue(0xCB, out cid);

                foreach (string dir in new string[] { "", "telecom", "msg" })
                {
                    b = new List<byte>(new byte[] { 0x02, 0x00 }); AddConn(b, cid); AddName(b, dir);
                    resp = Xfer(0x85, b);
                    if (resp[0] != 0xA0) throw new IOException("could not open folder '" + dir + "': " + Code(resp[0]));
                }

                b = new List<byte>(); AddConn(b, cid);
                AddHdr(b, 0x42, Encoding.ASCII.GetBytes("x-bt/MAP-msg-listing\0"));
                AddName(b, "inbox");
                AddHdr(b, 0x4C, new byte[] { 0x01, 0x02, 0x00, 0x00 });
                resp = Xfer(0x83, b);
                int size = -1, guard = 0;
                while (true)
                {
                    byte[] ap;
                    if (Headers(resp, 3).TryGetValue(0x4C, out ap))
                        for (int i = 0; i + 1 < ap.Length; i += 2 + ap[i + 1])
                            if (ap[i] == 0x12 && ap[i + 1] == 2 && i + 3 < ap.Length) size = (ap[i + 2] << 8) | ap[i + 3];
                    if (resp[0] != 0x90 || guard++ > 50) break;
                    b = new List<byte>(); AddConn(b, cid);
                    resp = Xfer(0x83, b);
                }
                bool ok = resp[0] == 0xA0;
                if (ok) Res("cs-phone-map", "PASS", phone.Name + " lets this laptop read messages (" + (size >= 0 ? size + " messages in inbox" : "size not reported") + "). Sending uses the same session.");
                else Res("cs-phone-map", "FAIL", phone.Name + " opened the session but refused the inbox listing: " + Code(resp[0]));

                b = new List<byte>(); AddConn(b, cid);
                try { Xfer(0x81, b); } catch { }
                sock.Dispose();
                if (ok) break;
            }
            catch (Exception e)
            {
                Res("cs-phone-map", "FAIL", phone.Name + " - " + Msg(e) + " (phone unlocked and nearby? Show Notifications ON for this laptop?)");
                if (sock != null) try { sock.Dispose(); } catch { }
            }
        }
        return 0;
    }
}
