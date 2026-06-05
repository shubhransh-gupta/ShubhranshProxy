# ShubhranshProxy

Native macOS HTTP(S) debugging proxy (Charles / Proxyman style). Capture traffic from **this Mac** and from **iPhone / Android** on the same Wi‑Fi.

---

## Requirements

| Item | Version |
|------|---------|
| macOS | 14+ |
| Xcode | 16+ recommended |
| iPhone / Android | Same Wi‑Fi as the Mac (for mobile capture) |

---

## Quick start (Mac only — 2 minutes)

1. Open **`ShubhranshProxy.xcodeproj`** in Xcode → **Product → Run** (⌘R).
2. Click **Start** (or **⌘⇧R**). Default listener: **`0.0.0.0:8888`** (Mac apps use **`127.0.0.1:8888`** via system proxy).
3. Leave **Route macOS traffic** enabled — Safari and most Mac apps are captured automatically.
4. Browse any site. Requests appear in the center table.

**HTTPS on Mac:** The root CA is installed automatically. Approve the one-time macOS password if prompted. SSL Proxying turns on by default.

---

## Full setup — Mac + iPhone (one go)

### Part A — Mac

1. **Build & run** ShubhranshProxy from Xcode.
2. Click **Start** (⌘⇧R).
3. Open **Proxy settings** (gear icon). Confirm:
   - **Listen Host** = `0.0.0.0` (All interfaces)
   - **Port** = `8888`
   - **Route macOS traffic** = ON
   - **Restore macOS Wi‑Fi/Ethernet proxy when stopping or quitting** = ON (recommended)
4. Open **SSL Proxy** tab. Confirm:
   - **Enable SSL Proxying** = ON
   - **Decrypt iPhone/Android traffic** = ON
   - Your API hosts are listed under **Hosts to decrypt** (e.g. `api-gateway.juno.lenskart.com`)
5. Note the **LAN IP(s)** shown under **Mobile devices** — e.g. `en0: 192.168.0.5:8888`.

### Part B — iPhone

1. **Same Wi‑Fi** as the Mac. Turn off VPN on the phone if capture fails.
2. **Install the root certificate**
   - In ShubhranshProxy: **SSL Proxy → AirDrop certificate to iPhone/iPad…**
   - On iPhone: accept AirDrop → **Settings → General → VPN & Device Management** → install the profile.
3. **Enable full trust (required for HTTPS)**
   - **Settings → General → About → Certificate Trust Settings**
   - Turn **ON** full trust for **ShubhranshProxy Root CA**
   - Without this step, you will only see `DEVICE /connected` or pink **TLS** errors — no API traffic.
4. **Configure Wi‑Fi proxy**
   - **Settings → Wi‑Fi → ⓘ** next to your network → **Configure Proxy → Manual**
   - **Server:** your Mac’s LAN IP from step A5 (e.g. `192.168.0.5`) — **never `127.0.0.1`**
   - **Port:** `8888`
   - **Authentication:** Off
5. **Verify**
   - Status bar in ShubhranshProxy should show **`1 mobile device connected`**
   - Open **Safari** on the iPhone and visit `https://example.com`
   - **Devices → All** in the sidebar should show **Mobile device** or **iPhone**
   - API calls appear in the session table with **Client** = `Mobile (192.168.x.x)` or `iPhone`

### Part C — When you are done

| Device | Action |
|--------|--------|
| **Mac** | Click **Stop** or quit ShubhranshProxy — system proxy is restored automatically |
| **iPhone** | **Settings → Wi‑Fi → ⓘ → Configure Proxy → Off** |

---

## Android (same Wi‑Fi)

1. AirDrop / export **ShubhranshProxy-Root-CA.cer** from **SSL Proxy → Save .cer for Android**.
2. Install as a **user CA** (Settings vary by OEM; usually **Security → Encryption & credentials → Install a certificate → CA certificate**).
3. **Wi‑Fi → your network → Advanced → Proxy → Manual**
   - Host: Mac LAN IP (e.g. `192.168.0.5`)
   - Port: `8888`
4. Android 7+ only trusts user CAs for apps that opt in; many apps use pinning. Test with Chrome first.

---

## Understanding the UI

### Session table columns

| Column | Meaning |
|--------|---------|
| **URL** | Request path or full URL |
| **Client** | `Mac`, app name, or `Mobile (IP)` / `iPhone` |
| **Method** | Color-coded: GET=blue, POST=green, DELETE=red, etc. |
| **Status** | HTTP status; **TLS** (pink) = HTTPS handshake failed on phone |
| **Time / Duration** | When the request ran and how long it took |

### Devices sidebar

- **Devices → All → Mac** — traffic from this Mac (system proxy → `127.0.0.1`)
- **Devices → All → Mobile device / iPhone** — traffic from phones on Wi‑Fi

`DEVICE /connected` rows are hidden from the table but mean the phone reached the proxy. Real API traffic should follow once the CA is trusted.

---

## HTTPS decryption

| Traffic source | Default behavior |
|----------------|------------------|
| **Mac** | Only hosts in **SSL Proxy → Hosts to decrypt** are MITM-decrypted (keeps Slack etc. working) |
| **iPhone / Android** | All HTTPS decrypted when **Decrypt iPhone/Android traffic** is ON |
| **Excluded hosts** | Never decrypted (banking, etc.) |

Pre-configured decrypt hosts (persisted):

- `api-gateway.juno.lenskart.com`
- `api-gateway.juno.preprod.lenskart.com`

Add more in **SSL Proxy → Host to decrypt → Add**.

---

## Troubleshooting

### Mac works, iPhone shows only `/connected` or nothing

| Check | Fix |
|-------|-----|
| Wrong proxy IP on iPhone | Use Mac **LAN IP** from SSL Proxy / Proxy settings, not `127.0.0.1` |
| Listen Host | Must be **`0.0.0.0`**. Stop → change in Proxy settings → Start |
| Certificate profile only | Also enable **Certificate Trust Settings** on iPhone (step B3) |
| Pink **TLS** rows in table | Tap row → inspector shows trust/pinning hint |
| Mac firewall | **System Settings → Network → Firewall** → allow ShubhranshProxy |
| Different networks | Mac and iPhone must be on the **same Wi‑Fi** |
| VPN on phone | Disable VPN while capturing |
| Native app vs Safari | Pinned apps (some production builds) block MITM — use **Safari** to verify setup |

### Status bar signals

```
Listening on all interfaces:8888 · devices → 192.168.0.5:8888 · 1 mobile device connected
```

- **No “mobile device connected”** → phone is not reaching the Mac (IP, firewall, or proxy off).
- **“mobile device connected” but no APIs** → certificate trust or app certificate pinning.

### Other Mac proxy still enabled

Turn off Proxyman / Charles if they use port 9090 or conflict with system proxy.

---

## Build from Terminal

```bash
cd /path/to/ShubhranshProxy
xcodebuild -scheme ShubhranshProxy -configuration Debug -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/*/Build/Products/Debug/ShubhranshProxy.app
```

## Run tests

```bash
xcodebuild test -scheme ShubhranshProxy -destination 'platform=macOS'
```

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘⇧R | Start / stop proxy |
| ⌘⇧K | Clear sessions |

---

## Project structure

```
ShubhranshProxy/
  App/              AppState, lifecycle
  Core/             Proxy engine, TLS, sessions, network helpers
  ProxyCore/        HTTP parsing, MITM, Map Local
  Features/         Inspector, favorites, HAR, breakpoints, rewrite, …
  UI/               Main window, sidebar, session table, setup guide
```

---

## License

Your project — add a license as needed.
