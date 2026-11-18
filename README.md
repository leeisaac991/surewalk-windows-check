# SURE Walk – Windows laptop check

Tells you whether a locked-down Windows laptop can run the **SURE Walk texting server** and the **iPhone Bluetooth bridge** with no install and no admin rights, and writes the results to a log.

It installs nothing, changes no settings, and sends no texts. The phone test asks the iPhone only *how many* messages are in its inbox and never reads their text. The log contains no message text and no phone numbers. It does include device names, like the name of your paired iPhone.

## Run it

1. Click **Code ▸ Download ZIP**. Right-click the zip, choose **Properties**, tick **Unblock**, click OK, then extract it.
2. Nothing else to download: the official Node.js Windows zip (LTS, from nodejs.org, MIT license) is included and gets unpacked automatically into `%LOCALAPPDATA%\surewalk-check` on the first run.
3. Pair the iPhone in **Settings ▸ Bluetooth & devices**. On the iPhone, go to **Settings ▸ Bluetooth ▸ (i)** next to the laptop and turn on **Show Notifications**. Keep the phone unlocked and nearby.
4. Double-click **`RUN-CHECK.cmd`**. When it finishes, `surewalk-check-log.txt` opens in Notepad.

`RUN-CHECK.cmd nophone` skips the phone connection.

## What it tries (each one is a fallback for the one before it)

| Step | Tool (all built into Windows unless noted) | What it checks |
|---|---|---|
| 1 | **cmd** | Admin status (just noted), whether you can write to your folders and the Startup folder, and whether programs and batch files run from your own folders |
| 2 | **cmd** | Which ways to run things exist: PowerShell, the C# compiler, Script Host, curl, Python, Node |
| 3 | **curl** | Whether GroupMe, jsDelivr and GitHub can be reached, and the proxy settings |
| 4 | **portable Node** (included zip) | Everything the texting server needs: a local dashboard port, file writes, Central time, and reaching GroupMe from Node |
| 5 | **PowerShell** | Bridge option A: the policies (AppLocker, App Control, restricted mode), the Bluetooth radio, the paired iPhone, and a real read-only connection to the iPhone's message service |
| 6 | **Windows Script Host** (JScript) | A fallback for when PowerShell is restricted: the Bluetooth hardware, the paired iPhone, and whether Windows has seen its message service |
| 5b | **PowerShell** | Calling: sets up the iPhone's hands-free (calling) link the way a car does, then disconnects. **It never places a call.** |
| 7 | **C# compiler** (`csc.exe`, part of .NET Framework) | Bridge option B: builds a small program in your own folder and runs the same phone test (skipped if step 5 already passed) |

The end of the log has a **SUMMARY** saying for each part whether it can run on this laptop, is blocked, or wasn't tested yet: the texting server, the iPhone bridge, start at login, GroupMe access, and calling.

## Excel link probe (can the Excel panel skip GroupMe?)

This checks whether the Excel texts panel can talk straight to a server on this laptop. If it can, GroupMe isn't needed for syncing. It changes nothing in the workbook or the texting setup.

1. Double-click **`PROBE-EXCEL-LINK.cmd`** and leave its window open. It runs a small test server that only this laptop can reach (`127.0.0.1:8788`).
2. Open [`excel-link/SURE-Walk-link-test.yaml`](excel-link/SURE-Walk-link-test.yaml), click **Raw**, and copy all of it.
3. In Excel on this laptop, open **Script Lab ▸ Import**, paste the text, and import it. Then open **SURE Walk link test** and click **Run all tests**.
   - If the browser asks to let the site access devices on your local network, click **Allow**.
   - If a small "SURE Walk link test window" opens, leave it open until the tests finish.
4. The results show in the panel and are saved to `excel-link-log.txt` next to `PROBE-EXCEL-LINK.cmd`.
