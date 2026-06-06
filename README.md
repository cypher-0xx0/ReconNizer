# ⚔️ ReconNizer — Automated Bug Bounty Recon Framework

```
██████╗ ███████╗ ██████╗ ██████╗ ███╗   ██╗███╗   ██╗██╗███████╗███████╗██████╗
██╔══██╗██╔════╝██╔════╝██╔═══██╗████╗  ██║████╗  ██║██║╚══███╔╝██╔════╝██╔══██╗
██████╔╝█████╗  ██║     ██║   ██║██╔██╗ ██║██╔██╗ ██║██║  ███╔╝ █████╗  ██████╔╝
██╔══██╗██╔══╝  ██║     ██║   ██║██║╚██╗██║██║╚██╗██║██║ ███╔╝  ██╔══╝  ██╔══██╗
██║  ██║███████╗╚██████╗╚██████╔╝██║ ╚████║██║ ╚████║██║███████╗███████╗██║  ██║
╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═══╝╚═╝╚══════╝╚══════╝╚═╝  ╚═╝

              ► Automated Recon Framework ◄
       Subdomains • Crawling • Analysis • Reporting
```

> **For authorized security testing and bug bounty programs only. Always ensure you have explicit permission before running recon on any target.**

---

## What is ReconNizer?

ReconNizer is a fully automated reconnaissance framework built for bug bounty hunters. It runs a complete recon pipeline from subdomain discovery to URL categorization, takes screenshots of all live hosts, and delivers every result directly to your Discord server in real time — so you can monitor progress and start testing while the script is still running.

---

## Features

- 🔍 **Passive subdomain discovery** via 7 sources (Wayback, CRT.sh, AbuseIPDB, Findomain, Subfinder, Amass, Assetfinder)
- 🔀 **Subdomain permutation** with AlterX for extended coverage
- 🧬 **DNS resolution** via DnsX + ShuffleDNS with custom resolvers
- 🟢 **Live host detection** with HttpX (status codes + tech detection)
- 📸 **Automatic screenshots** of all alive hosts via Gowitness
- 🌐 **Multi-source URL collection** — GAU, Katana, Waymore, OTX, JS file mining
- 🗂️ **Smart URL categorization** — 13 categories auto-sorted (API, auth, admin, upload, SSRF, etc.)
- 📡 **Real-time Discord notifications** — progress alerts + every output file delivered as an attachment
- 🤖 **Local LLM analysis** (optional) — attack surface mapping and priority target ranking via Ollama

---

## Pipeline Overview

```
Target Domain
     │
     ▼
┌─────────────────────────────┐
│  SubEnum.sh (7 sources)     │  Passive subdomain discovery
└────────────┬────────────────┘
             │
             ▼
┌─────────────────────────────┐
│  AlterX                     │  Permutation & mutation
└────────────┬────────────────┘
             │
             ▼
┌─────────────────────────────┐
│  DnsX + ShuffleDNS          │  DNS resolution + bruteforce
└────────────┬────────────────┘
             │
             ▼
┌─────────────────────────────┐
│  HttpX                      │  Alive host detection + tech detect
└────────────┬────────────────┘
             │
             ▼
┌─────────────────────────────┐
│  Gowitness                  │  Screenshots of all live hosts
└────────────┬────────────────┘
             │
             ▼
┌─────────────────────────────┐
│  GAU + Katana + Waymore     │  URL collection (7 sources)
│  + OTX + JS Mining          │
└────────────┬────────────────┘
             │
             ▼
┌─────────────────────────────┐
│  URL Categorization         │  13 smart categories
└────────────┬────────────────┘
             │
             ▼
┌─────────────────────────────┐
│  Discord Delivery           │  All files + summary sent live
└────────────┬────────────────┘
             │
             ▼
┌─────────────────────────────┐
│  LLM Analysis (optional)    │  Priority targets + attack map
└─────────────────────────────┘
```

---

## Requirements

### System
- Linux (Kali, Ubuntu, Parrot, or any Debian-based distro)
- Bash 4+
- Python 3.x (for the optional LLM module)
- `curl`, `zip`, `awk`, `sort` (standard utilities)

### Tools — Install All

```bash
# Go-based tools (ProjectDiscovery suite)
go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install github.com/projectdiscovery/dnsx/cmd/dnsx@latest
go install github.com/projectdiscovery/httpx/cmd/httpx@latest
go install github.com/projectdiscovery/katana/cmd/katana@latest
go install github.com/projectdiscovery/alterx/cmd/alterx@latest
go install github.com/projectdiscovery/notify/cmd/notify@latest

# ShuffleDNS
go install github.com/projectdiscovery/shuffledns/cmd/shuffledns@latest

# Amass
go install github.com/owasp-amass/amass/v4/...@master

# Findomain
curl -LO https://github.com/Findomain/Findomain/releases/latest/download/findomain-linux
chmod +x findomain-linux && mv findomain-linux /usr/local/bin/findomain

# Assetfinder
go install github.com/tomnomnom/assetfinder@latest

# GAU
go install github.com/lc/gau/v2/cmd/gau@latest

# Gowitness
go install github.com/sensepost/gowitness@latest

# Waymore
pip install waymore

# SubEnum wrapper (required)
# https://github.com/bing0o/SubEnum
git clone https://github.com/bing0o/SubEnum
cd SubEnum && chmod +x subenum.sh && cp subenum.sh /usr/local/bin/subenum.sh
```

### Resolvers File
ShuffleDNS requires a resolvers list. Place it at `/home/cypherx/payloads/resolvers.txt` or update the path in the script.

```bash
# Download a good public resolvers list
curl -L https://raw.githubusercontent.com/trickest/resolvers/main/resolvers.txt \
    -o /home/cypherx/payloads/resolvers.txt
```

---

## Setup

### 1. Clone the repo

```bash
git clone https://github.com/yourusername/reconnizer
cd reconnizer
chmod +x recon.sh
```

### 2. Configure Discord

**Create a Discord webhook:**
1. Open your Discord server
2. Go to **Channel Settings → Integrations → Webhooks → New Webhook**
3. Copy the webhook URL

**Edit `recon.sh` and set your webhook:**
```bash
DISCORD_WEBHOOK="https://discord.com/api/webhooks/YOUR_ID/YOUR_TOKEN"
```

**Set up Notify config** at `~/.config/notify/provider-config.yaml`:
```yaml
discord:
  - id: "recon-alerts"
    discord_channel: "recon-alerts"
    discord_username: "ReconBot"
    discord_format: "{{data}}"
    discord_webhook_url: "https://discord.com/api/webhooks/YOUR_ID/YOUR_TOKEN"
```

**Test it:**
```bash
echo "ReconNizer is ready" | notify -provider discord -id recon-alerts
```

### 3. Configure Waymore API Keys (optional but recommended)

Edit `~/.config/waymore/config.yml`:
```yaml
virustotal_api_key: YOUR_VT_FREE_API_KEY
urlscan_api_key: YOUR_URLSCAN_API_KEY
```

> VirusTotal free tier = 4 requests/min. The script uses `-p 2` (2 parallel requests) to stay within limits automatically.

---

## Usage

```bash
./recon.sh <target>
```

**Examples:**
```bash
./recon.sh example.com
./recon.sh target.com
```

---

## Output Structure

All results are saved to `recon_<target>/`:

```
recon_target.com/
├── subs.txt                   # Raw passive subdomain results
├── subdomains.txt             # After AlterX permutations
├── dnsx_resolved.txt          # DnsX resolved
├── shuffledns_subs.txt        # ShuffleDNS resolved
├── resolved_subdomains.txt    # Final merged + deduplicated
├── alive_subdomains.txt       # Live hosts with status + tech
│
├── gowitness/
│   ├── gowitness_targets.txt  # Clean URL list for gowitness
│   └── screenshots/           # JPEG screenshots of all live hosts
│
├── urls_gau.txt               # GAU results
├── urls_katana.txt            # Katana crawl results
├── urls_waymore.txt           # Waymore results (WB+CC+OTX+URLScan+VT)
├── urls_otx.txt               # OTX AlienVault
├── urls_js_mined.txt          # Endpoints extracted from JS files
├── js_files_to_mine.txt       # JS files list used for mining
├── all_urls.txt               # All sources merged + deduplicated
│
├── api_urls.txt               # /api/, graphql, swagger, etc.
├── auth_urls.txt              # login, oauth, jwt, sso, etc.
├── registration_urls.txt      # signup, register, etc.
├── password_urls.txt          # reset, forgot, recover, etc.
├── upload_urls.txt            # upload, import, attachment, etc.
├── admin_urls.txt             # admin, dashboard, panel, etc.
├── payment_urls.txt           # checkout, billing, wallet, etc.
├── account_urls.txt           # profile, settings, member, etc.
├── documents.txt              # .pdf, .doc, .xls, .csv, etc.
├── sensitive_files.txt        # .bak, .env, .sql, .config, etc.
├── js_files.txt               # All .js files found
├── ssrf_candidates.txt        # url=, redirect=, fetch=, proxy=, etc.
└── redirect_candidates.txt    # Open redirect parameter patterns
```

---

## Discord Notifications

The script sends the following to Discord automatically during the run:

| Event | Type |
|---|---|
| Recon started | Message with timestamp |
| Subdomains resolved | Count + `resolved_subdomains.txt` file |
| Live hosts found | Count + `alive_subdomains.txt` file |
| Screenshots captured | Count + top 20 screenshots as images |
| Screenshots > 20 | Full ZIP archive |
| URL collection done | Count breakdown per source |
| All categorized files | 13 files as attachments with counts |
| Final summary | Full stats box in code block |

---

## Optional: LLM Attack Surface Analysis

After recon completes you can feed all results into a local LLM via Ollama to get prioritized targets and an HTML attack map.

### Setup Ollama

```bash
curl -fsSL https://ollama.com/install.sh | sh
ollama pull llama3
ollama serve
```

### Run the analyzer

```bash
python3 recon_ai.py recon_target.com target.com llama3 "https://discord.com/api/webhooks/..."
```

This produces:
- `attack_surface.json` — structured list of top 15 targets with severity, vuln type, and reasoning
- `attack_surface_map.html` — dark-themed visual attack map, open in any browser
- Top 5 targets posted directly to Discord as a formatted message

**Supported models:**

| Model | Notes |
|---|---|
| `llama3` | Good default, solid JSON output |
| `mistral` | Faster, good for quick analysis |
| `deepseek-coder` | Better at understanding API patterns |
| `llama3:70b` | Best quality, needs 40GB+ VRAM |

---

## URL Sources

| Source | Type | Provider |
|---|---|---|
| GAU | Passive | Wayback + OTX + CommonCrawl + URLScan |
| Katana | Active | Crawls all alive subdomains, depth 3, JS parsing |
| Waymore | Passive | Wayback + CommonCrawl + OTX + URLScan + VirusTotal |
| OTX AlienVault | Passive | Threat intel URL feed |
| JS Mining | Active | Re-crawls all discovered JS files for hidden endpoints |

---

## Subdomain Sources

| Source | Method |
|---|---|
| Wayback Machine | Archive |
| CRT.sh | Certificate transparency |
| AbuseIPDB | Passive |
| Findomain | Passive multi-source |
| Subfinder | Passive multi-source |
| Amass | Passive + active |
| Assetfinder | Passive |
| AlterX | Permutation / mutation |
| ShuffleDNS | DNS bruteforce |

---

## Customization

**Change the resolvers path:**
```bash
# In recon.sh, find and update:
shuffledns -list ... -r /your/path/resolvers.txt
```

**Change max screenshots sent to Discord:**
```bash
# In recon.sh:
MAX_SEND=20   # increase or decrease as needed
```

**Change Katana crawl depth:**
```bash
# -d 3 = follow links 3 levels deep
katana -list - -kf all -jc -jsl -d 3 ...
```

**Add or remove Waymore providers:**
```bash
waymore ... --providers wayback,commoncrawl,otx,urlscan,virustotal
```

---

## Legal Disclaimer

This tool is intended for **authorized security testing only**, including bug bounty programs where you have explicit permission from the target organization. Unauthorized use against systems you do not have permission to test is illegal and unethical. The author is not responsible for any misuse of this tool.

Always follow the scope and rules of engagement of the program you are participating in.

---

## Author

Built by **CypherX** — bug bounty hunter & security researcher.

---

## Acknowledgements

This framework wraps and automates tools built by the community. Credit to:

- [ProjectDiscovery](https://github.com/projectdiscovery) — Subfinder, DnsX, HttpX, Katana, AlterX, Notify, ShuffleDNS
- [bing0o](https://github.com/bing0o) — SubEnum
- [lc](https://github.com/lc) — GAU
- [sensepost](https://github.com/sensepost) — Gowitness
- [xnl-h4ck3r](https://github.com/xnl-h4ck3r) — Waymore
- [OWASP](https://github.com/owasp-amass) — Amass
- [Findomain](https://github.com/Findomain) — Findomain
- [tomnomnom](https://github.com/tomnomnom) — Assetfinder
- [Ollama](https://ollama.com) — Local LLM runtime
