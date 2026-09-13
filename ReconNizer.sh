#!/bin/bash
set -uo pipefail


TARGET="${1:-}"
OUTPUT_DIR="recon_${TARGET}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

DISCORD_WEBHOOK="https://discord.com/api/webhooks/xyz" ## Put Your Discord Webhook Here
RESOLVERS="${RESOLVERS:-/home/cypherx/payloads/resolvers.txt}"
MAX_SEND=20
GOWITNESS_CHROME_ARGS="--no-sandbox,--disable-gpu,--disable-dev-shm-usage,--single-process,--disable-extensions"
GOWITNESS_THREADS="${GOWITNESS_THREADS:-2}"
GOWITNESS_TIMEOUT="${GOWITNESS_TIMEOUT:-15}"

REQUIRED_TOOLS=(subenum.sh alterx dnsx shuffledns subfaster naabu httpx gowitness gau katana nuclei curl zip)

# ── Helpers ─────────────────────────────────────────────────────────
section() {
    echo
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  [+] $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
}

count() { [ -f "$1" ] && wc -l < "$1" || echo 0; }


json_escape() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])' 2>/dev/null \
        || printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g'
}

notify_msg() {
    command -v notify >/dev/null 2>&1 || return 0
    echo "$1" | notify -provider discord -id recon-alerts -silent 2>/dev/null
}

discord_msg() {
    local escaped
    escaped=$(json_escape "$1")
    curl -s -X POST "$DISCORD_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "{\"content\": \"${escaped}\"}" > /dev/null
}

discord_file() {
    local file="$1"
    local msg="$2"
    local escaped
    if [ -f "$file" ] && [ -s "$file" ]; then
      
        escaped=$(json_escape "$msg")
        curl -s -X POST "$DISCORD_WEBHOOK" \
            -F "payload_json={\"content\": \"${escaped}\"}" \
            -F "file=@$file" > /dev/null
        echo -e "${GREEN}  [✓] Sent to Discord: $(basename "$file")${NC}"
    else
        echo -e "${YELLOW}  [~] Skipped (empty): $(basename "$file")${NC}"
    fi
}

send_screenshots_to_discord() {
    local shots_dir="$1"
    local label_prefix="$2"
    local max_send="${3:-$MAX_SEND}"

    local shot_count
    shot_count=$(find "$shots_dir" -type f \( -name "*.jpeg" -o -name "*.png" \) 2>/dev/null | wc -l)

    if [ "$shot_count" -eq 0 ]; then
        echo -e "${YELLOW}  [~] No screenshots found in $shots_dir — skipping upload.${NC}"
        return 0
    fi

    discord_msg "📸 **[$TARGET] $label_prefix Screenshots** — $shot_count total captured. Uploading top $max_send..."

    local sent_list_file
    sent_list_file=$(mktemp)
    find "$shots_dir" -type f \( -name "*.jpeg" -o -name "*.png" \) | sort | head -n "$max_send" > "$sent_list_file"

    local sent=0
    while IFS= read -r screenshot; do
        local filename label escaped_label
        filename=$(basename "$screenshot")
        label=$(echo "$filename" | sed 's/[_-]/ /g' | sed 's/\..*//')
        escaped_label=$(json_escape "🖼️ \`$label_prefix: $label\`")

        curl -s -X POST "$DISCORD_WEBHOOK" \
            -F "payload_json={\"content\": \"${escaped_label}\"}" \
            -F "file=@$screenshot" > /dev/null

        sent=$((sent + 1))
        echo -e "${GREEN}  [✓] Sent screenshot $sent/$max_send: $filename${NC}"
        sleep 0.5
    done < "$sent_list_file"

    if [ "$shot_count" -gt "$max_send" ]; then
        echo -e "${YELLOW}  [~] Zipping the remaining $label_prefix screenshots (excluding the $max_send already sent)...${NC}"
        local remaining_zip
        remaining_zip="${shots_dir%/}_remaining.zip"

        find "$shots_dir" -type f \( -name "*.jpeg" -o -name "*.png" \) | sort \
            | tail -n +"$((max_send + 1))" \
            | zip -q -j "$remaining_zip" -@ 2>/dev/null

        discord_file "$remaining_zip" "📦 **[$TARGET] $label_prefix — Remaining $((shot_count - max_send)) Screenshots (ZIP)**"
    fi

    rm -f "$sent_list_file"
    notify_msg "📸 [Recon: $TARGET] $label_prefix screenshots done: $shot_count captured"
}

check_deps() {
    local missing=()
    for tool in "${REQUIRED_TOOLS[@]}"; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}[!] Missing required tools: ${missing[*]}${NC}"
        echo -e "${RED}    Install/PATH-fix these before running.${NC}"
        exit 1
    fi
}

# ── Preflight ───────────────────────────────────────────────────────
if [ -z "$TARGET" ]; then
    echo -e "${RED}[!] Usage: $0 <target-domain>${NC}"
    exit 1
fi

if [ "$DISCORD_WEBHOOK" = "PASTE_YOUR_DISCORD_WEBHOOK_URL_HERE" ] || [ -z "$DISCORD_WEBHOOK" ]; then
    echo -e "${RED}[!] Edit this script and set DISCORD_WEBHOOK near the top to your real webhook URL.${NC}"
    exit 1
fi

check_deps
mkdir -p "$OUTPUT_DIR"

if [ ! -f "$RESOLVERS" ]; then
    echo -e "${YELLOW}[~] Resolver list not found at $RESOLVERS — shuffledns step may fail.${NC}"
    echo -e "${YELLOW}    Set RESOLVERS=/path/to/resolvers.txt to override.${NC}"
fi

echo -e "
██████╗ ███████╗ ██████╗ ██████╗ ███╗   ██╗███╗   ██╗██╗███████╗███████╗██████╗
██╔══██╗██╔════╝██╔════╝██╔═══██╗████╗  ██║████╗  ██║██║╚══███╔╝██╔════╝██╔══██╗
██████╔╝█████╗  ██║     ██║   ██║██╔██╗ ██║██╔██╗ ██║██║  ███╔╝ █████╗  ██████╔╝
██╔══██╗██╔══╝  ██║     ██║   ██║██║╚██╗██║██║╚██╗██║██║ ███╔╝  ██╔══╝  ██╔══██╗
██║  ██║███████╗╚██████╗╚██████╔╝██║ ╚████║██║ ╚████║██║███████╗███████╗██║  ██║
╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═══╝╚═╝╚══════╝╚══════╝╚═╝  ╚═╝

                  ► Automated Recon Framework ◄
           Subdomains • Crawling • Analysis • Reporting
"

discord_msg "🚀 **Recon Started** | Target: \`$TARGET\` | $(date '+%Y-%m-%d %H:%M:%S')"

# ─────────────────────────────────────────────────────────────────────
section "SubEnum — Passive Subdomain Discovery"
subenum.sh -d "$TARGET" \
    -u wayback,crt,abuseipdb,Findomain,Subfinder,Amass,Assetfinder \
    -o "$OUTPUT_DIR/subs.txt"

# ─────────────────────────────────────────────────────────────────────
section "AlterX — Subdomain Permutations"
alterx -l "$OUTPUT_DIR/subs.txt" -o "$OUTPUT_DIR/subdomains.txt"

if [ ! -s "$OUTPUT_DIR/subdomains.txt" ]; then
    echo -e "${RED}[!] subdomains.txt empty or not found — subenum/alterx failed.${NC}"
    discord_msg "❌ **Recon Failed** | Target: \`$TARGET\` | subenum/alterx produced no output."
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────
section "DnsX — DNS Resolution"
dnsx -l "$OUTPUT_DIR/subdomains.txt" -o "$OUTPUT_DIR/dnsx_resolved.txt"

# ─────────────────────────────────────────────────────────────────────
section "ShuffleDNS — Bruteforce Resolution"
shuffledns -list "$OUTPUT_DIR/subdomains.txt" \
    -r "$RESOLVERS" \
    -o "$OUTPUT_DIR/shuffledns_subs.txt"

section "Running Subfaster..."
subfaster -d "$TARGET" -o "$OUTPUT_DIR/subfaster_subs.txt"

cat "$OUTPUT_DIR/dnsx_resolved.txt" "$OUTPUT_DIR/shuffledns_subs.txt" "$OUTPUT_DIR/subfaster_subs.txt" 2>/dev/null \
    | sort -u > "$OUTPUT_DIR/resolved_subdomains.txt"

if [ ! -s "$OUTPUT_DIR/resolved_subdomains.txt" ]; then
    echo -e "${RED}[!] No resolved subdomains found.${NC}"
    discord_msg "❌ **Recon Failed** | Target: \`$TARGET\` | DNS resolution produced no output."
    exit 1
fi

SUB_COUNT=$(count "$OUTPUT_DIR/resolved_subdomains.txt")
echo -e "${GREEN}  [✓] Found $SUB_COUNT resolved subdomains${NC}"

notify_msg "✅ [Recon: $TARGET] Subdomains resolved: $SUB_COUNT"
discord_file "$OUTPUT_DIR/resolved_subdomains.txt" "📋 **[$TARGET] Resolved Subdomains** — $SUB_COUNT hosts"

# ─────────────────────────────────────────────────────────────────────
section "HttpX — Alive Host Detection"
httpx -l "$OUTPUT_DIR/resolved_subdomains.txt" \
    -sc -mc 200,301,302,403 \
    -title -tech-detect \
    -silent \
    -o "$OUTPUT_DIR/alive_subdomains.txt"

if [ ! -s "$OUTPUT_DIR/alive_subdomains.txt" ]; then
    echo -e "${RED}[!] alive_subdomains.txt empty or not found — httpx failed.${NC}"
    discord_msg "❌ **HttpX Failed** | Target: \`$TARGET\`"
    exit 1
fi

ALIVE_COUNT=$(count "$OUTPUT_DIR/alive_subdomains.txt")
echo -e "${GREEN}  [✓] Found $ALIVE_COUNT alive hosts${NC}"

notify_msg "✅ [Recon: $TARGET] Live hosts: $ALIVE_COUNT"
discord_file "$OUTPUT_DIR/alive_subdomains.txt" "🟢 **[$TARGET] Alive Hosts** — $ALIVE_COUNT live (with status codes + tech)"

# ─────────────────────────────────────────────────────────────────────
section "Naabu For Portscanning"

dnsx -l "$OUTPUT_DIR/resolved_subdomains.txt" -a -resp-only -o "$OUTPUT_DIR/ips.txt"
naabu -c 250 -l "$OUTPUT_DIR/ips.txt" \
    -p 3000,5000,8080,8000,8081,8888,8069,8009,8001,8070,8088,8002,8060,8091,8086,8010,8050,8085,8089,8040,8020,8051,8087,8071,8011,8030,8061,8072,8100,8083,8073,8099,8092,8074,8043,8035,8055,8021,8093,8022,8075,8044,8062,8023,8094,8012,8033,8063,8045,7000,9000,7070,9001,7001,10000,9002,7002,9003,7003,10001,80,443,4443 \
    -o "$OUTPUT_DIR/Open_ports.txt"

OPEN_PORTS=$(count "$OUTPUT_DIR/Open_ports.txt")
discord_file "$OUTPUT_DIR/Open_ports.txt" "🟢 **[$TARGET] Open Ports** — $OPEN_PORTS"

section "Alive Open Ports"
httpx -l "$OUTPUT_DIR/Open_ports.txt" \
    -sc -mc 200,301,302,403 \
    -title -tech-detect \
    -silent \
    -o "$OUTPUT_DIR/alive_ports.txt"

ALIVE_PORTS=$(count "$OUTPUT_DIR/alive_ports.txt")
discord_file "$OUTPUT_DIR/alive_ports.txt" "🟢 **[$TARGET] Alive Open Ports** — $ALIVE_PORTS"

# ─────────────────────────────────────────────────────────────────────
section "Gowitness — Screenshots"


GOWITNESS_DIR="$OUTPUT_DIR/gowitness"
GOWITNESS_SHOTS="$GOWITNESS_DIR/screenshots"
mkdir -p "$GOWITNESS_SHOTS"

awk '{print $1}' "$OUTPUT_DIR/alive_subdomains.txt" > "$GOWITNESS_DIR/gowitness_targets.txt"

echo -e "${YELLOW}  [~] Screenshotting $(count "$GOWITNESS_DIR/gowitness_targets.txt") targets (threads=$GOWITNESS_THREADS, timeout=${GOWITNESS_TIMEOUT}s)...${NC}"

gowitness scan file \
    -f "$GOWITNESS_DIR/gowitness_targets.txt" \
    -s "$GOWITNESS_SHOTS" \
    --write-none \
    --threads "$GOWITNESS_THREADS" \
    --timeout "$GOWITNESS_TIMEOUT" \
    --delay 2 \
    --screenshot-format jpeg \
    --screenshot-jpeg-quality 70 \
    --chrome-args="$GOWITNESS_CHROME_ARGS" \
    -q

SHOT_COUNT=$(find "$GOWITNESS_SHOTS" \( -name "*.jpeg" -o -name "*.png" \) 2>/dev/null | wc -l)
echo -e "${GREEN}  [✓] Captured $SHOT_COUNT screenshots${NC}"

section "Sending Subdomain Screenshots to Discord"
send_screenshots_to_discord "$GOWITNESS_SHOTS" "Subdomains"

# ─────────────────────────────────────────────────────────────────────
section "Gowitness — Screenshots (Alive Open Ports)"

GOWITNESS_PORTS_DIR="$OUTPUT_DIR/gowitness_ports"
GOWITNESS_PORTS_SHOTS="$GOWITNESS_PORTS_DIR/screenshots"
mkdir -p "$GOWITNESS_PORTS_SHOTS"

if [ -s "$OUTPUT_DIR/alive_ports.txt" ]; then
    awk '{print $1}' "$OUTPUT_DIR/alive_ports.txt" > "$GOWITNESS_PORTS_DIR/gowitness_targets.txt"


    sed -E 's~^[a-zA-Z]+://~~; s~/.*$~~' "$GOWITNESS_PORTS_DIR/gowitness_targets.txt" \
        | sort -u > "$GOWITNESS_PORTS_DIR/ip_port_list.txt"

    IP_PORT_COUNT=$(count "$GOWITNESS_PORTS_DIR/ip_port_list.txt")

    echo -e "${GREEN}  [✓] $IP_PORT_COUNT unique IP:PORT targets going into screenshots:${NC}"
    cat "$GOWITNESS_PORTS_DIR/ip_port_list.txt" | sed 's/^/      /'

    discord_file "$GOWITNESS_PORTS_DIR/ip_port_list.txt" "🌐 **[$TARGET] IP:PORT List (Open Ports)** — $IP_PORT_COUNT targets — screenshots follow below"

    echo -e "${YELLOW}  [~] Screenshotting $IP_PORT_COUNT open-port targets (threads=$GOWITNESS_THREADS, timeout=${GOWITNESS_TIMEOUT}s)...${NC}"

    gowitness scan file \
        -f "$GOWITNESS_PORTS_DIR/gowitness_targets.txt" \
        -s "$GOWITNESS_PORTS_SHOTS" \
        --write-none \
        --threads "$GOWITNESS_THREADS" \
        --timeout "$GOWITNESS_TIMEOUT" \
        --delay 2 \
        --screenshot-format jpeg \
        --screenshot-jpeg-quality 70 \
        --chrome-args="$GOWITNESS_CHROME_ARGS" \
        -q

    PORT_SHOT_COUNT=$(find "$GOWITNESS_PORTS_SHOTS" \( -name "*.jpeg" -o -name "*.png" \) 2>/dev/null | wc -l)
    echo -e "${GREEN}  [✓] Captured $PORT_SHOT_COUNT screenshots from alive open ports${NC}"

    section "Sending Open-Port Screenshots to Discord"
    send_screenshots_to_discord "$GOWITNESS_PORTS_SHOTS" "Open Ports"
else
    echo -e "${YELLOW}  [~] alive_ports.txt empty — skipping open-port screenshots.${NC}"
fi

# ─────────────────────────────────────────────────────────────────────
section "URL Collection — Multi Source"


echo -e "${YELLOW}  [~] Running GAU...${NC}"
gau "$TARGET" --subs \
    --providers wayback,otx,commoncrawl,urlscan \
    --threads 5 --retries 2 \
    --blacklist png,jpg,gif,jpeg,svg,ico,woff,woff2,ttf,eot,mp4,mp3 \
    > "$OUTPUT_DIR/urls_gau.txt" 2>/dev/null
echo -e "${GREEN}  [✓] GAU: $(count "$OUTPUT_DIR/urls_gau.txt") URLs${NC}"

echo -e "${YELLOW}  [~] Running Katana...${NC}"
awk '{print $1}' "$OUTPUT_DIR/alive_subdomains.txt" | \
katana -list - -kf all -jc -jsl -d 3 -c 20 -p 10 -timeout 10 -aff -silent \
    -o "$OUTPUT_DIR/urls_katana.txt" 2>/dev/null
echo -e "${GREEN}  [✓] Katana: $(count "$OUTPUT_DIR/urls_katana.txt") URLs${NC}"

echo -e "${YELLOW}  [~] Mining JS files for hidden endpoints...${NC}"
grep -hEi '\.js(\?|$)' "$OUTPUT_DIR/urls_gau.txt" "$OUTPUT_DIR/urls_katana.txt" 2>/dev/null \
    | sort -u > "$OUTPUT_DIR/js_files_to_mine.txt"
if [ -s "$OUTPUT_DIR/js_files_to_mine.txt" ]; then
    katana -list "$OUTPUT_DIR/js_files_to_mine.txt" -kf all -jc -jsl -silent \
        -o "$OUTPUT_DIR/urls_js_mined.txt" 2>/dev/null || true
fi
echo -e "${GREEN}  [✓] JS Mined: $(count "$OUTPUT_DIR/urls_js_mined.txt") endpoints${NC}"

echo -e "${YELLOW}  [~] Merging all sources...${NC}"
cat \
    "$OUTPUT_DIR/urls_gau.txt" \
    "$OUTPUT_DIR/urls_katana.txt" \
    "$OUTPUT_DIR/urls_js_mined.txt" \
    2>/dev/null \
    | grep -Ei '^https?://' \
    | sed 's/#.*//' \
    | sort -u > "$OUTPUT_DIR/all_urls.txt"

URL_COUNT=$(count "$OUTPUT_DIR/all_urls.txt")

echo
echo -e "${BLUE}  ┌─ URL Sources Breakdown ─────────────────────────────┐${NC}"
echo -e "${BLUE}  │${NC}  GAU (Wayback+OTX+CC+URLScan) : $(printf "%-8s" "$(count "$OUTPUT_DIR/urls_gau.txt")")              ${BLUE}│${NC}"
echo -e "${BLUE}  │${NC}  Katana (active crawl)        : $(printf "%-8s" "$(count "$OUTPUT_DIR/urls_katana.txt")")              ${BLUE}│${NC}"
echo -e "${BLUE}  │${NC}  JS File Mining               : $(printf "%-8s" "$(count "$OUTPUT_DIR/urls_js_mined.txt")")              ${BLUE}│${NC}"
echo -e "${BLUE}  │${NC}  ─────────────────────────────────────────────  ${BLUE}│${NC}"
echo -e "${BLUE}  │${NC}  TOTAL UNIQUE                 : ${GREEN}$(printf "%-8s" "$URL_COUNT")${NC}              ${BLUE}│${NC}"
echo -e "${BLUE}  └─────────────────────────────────────────────────────┘${NC}"

notify_msg "✅ [Recon: $TARGET] $URL_COUNT unique URLs — GAU(Wayback+OTX+CC+URLScan)+Katana+JSMining"

# ─────────────────────────────────────────────────────────────────────
section "URL Categorization"
U="$OUTPUT_DIR/all_urls.txt"

grep -Ei '/api/|/v[0-9]/|graphql|swagger|openapi|ajax|rpc'                                          "$U" > "$OUTPUT_DIR/api_urls.txt"             || true
grep -Ei 'login|signin|auth|oauth|sso|token|jwt|authenticate'                                        "$U" > "$OUTPUT_DIR/auth_urls.txt"            || true
grep -Ei 'register|signup|create-account|join|new-account'                                           "$U" > "$OUTPUT_DIR/registration_urls.txt"    || true
grep -Ei 'reset|forgot|recover|change-password|password-reset'                                       "$U" > "$OUTPUT_DIR/password_urls.txt"        || true
grep -Ei 'upload|import|attachment|avatar|file|document|media'                                       "$U" > "$OUTPUT_DIR/upload_urls.txt"          || true
grep -Ei 'admin|administrator|manage|dashboard|console|panel|backend'                                "$U" > "$OUTPUT_DIR/admin_urls.txt"           || true
grep -Ei '\.(pdf|doc|docx|xls|xlsx|ppt|pptx|csv)$'                                                  "$U" > "$OUTPUT_DIR/documents.txt"            || true
grep -Ei '\.(bak|old|backup|zip|tar|gz|7z|rar|sql|db|env|yml|yaml|conf|config)$'                    "$U" > "$OUTPUT_DIR/sensitive_files.txt"      || true
grep -Ei 'payment|checkout|billing|invoice|wallet|subscription|purchase|cart'                        "$U" > "$OUTPUT_DIR/payment_urls.txt"         || true
grep -Ei 'profile|account|settings|preferences|user|member|customer'                                 "$U" > "$OUTPUT_DIR/account_urls.txt"         || true
grep -Ei 'url=|uri=|link=|redirect=|return=|next=|dest=|destination=|continue=|callback=|feed=|fetch=|proxy=' \
                                                                                                      "$U" > "$OUTPUT_DIR/ssrf_candidates.txt"      || true
grep -Ei 'redirect=|return=|returnUrl=|return_url=|next=|continue=|dest=|destination=|callback='    "$U" > "$OUTPUT_DIR/redirect_candidates.txt"  || true
grep -Ei '\.js$'                                                                                      "$U" > "$OUTPUT_DIR/js_files.txt"             || true

# ─────────────────────────────────────────────────────────────────────
section "Sending Categorized Files to Discord"

discord_file "$OUTPUT_DIR/api_urls.txt"            "🔌 **[$TARGET] API Endpoints** — $(count "$OUTPUT_DIR/api_urls.txt") found"
discord_file "$OUTPUT_DIR/auth_urls.txt"           "🔐 **[$TARGET] Auth Endpoints** — $(count "$OUTPUT_DIR/auth_urls.txt") found"
discord_file "$OUTPUT_DIR/registration_urls.txt"   "📝 **[$TARGET] Registration Pages** — $(count "$OUTPUT_DIR/registration_urls.txt") found"
discord_file "$OUTPUT_DIR/password_urls.txt"       "🔑 **[$TARGET] Password Reset Pages** — $(count "$OUTPUT_DIR/password_urls.txt") found"
discord_file "$OUTPUT_DIR/upload_urls.txt"         "📤 **[$TARGET] Upload Features** — $(count "$OUTPUT_DIR/upload_urls.txt") found"
discord_file "$OUTPUT_DIR/admin_urls.txt"          "🛡️ **[$TARGET] Admin Panels** — $(count "$OUTPUT_DIR/admin_urls.txt") found"
discord_file "$OUTPUT_DIR/payment_urls.txt"        "💳 **[$TARGET] Payment Endpoints** — $(count "$OUTPUT_DIR/payment_urls.txt") found"
discord_file "$OUTPUT_DIR/account_urls.txt"        "👤 **[$TARGET] Account Endpoints** — $(count "$OUTPUT_DIR/account_urls.txt") found"
discord_file "$OUTPUT_DIR/documents.txt"           "📄 **[$TARGET] Documents** — $(count "$OUTPUT_DIR/documents.txt") found"
discord_file "$OUTPUT_DIR/sensitive_files.txt"     "⚠️ **[$TARGET] Sensitive Files** — $(count "$OUTPUT_DIR/sensitive_files.txt") found"
discord_file "$OUTPUT_DIR/js_files.txt"            "📜 **[$TARGET] JS Files** — $(count "$OUTPUT_DIR/js_files.txt") found"
discord_file "$OUTPUT_DIR/ssrf_candidates.txt"     "🎯 **[$TARGET] SSRF Candidates** — $(count "$OUTPUT_DIR/ssrf_candidates.txt") found"
discord_file "$OUTPUT_DIR/redirect_candidates.txt" "↪️ **[$TARGET] Redirect Candidates** — $(count "$OUTPUT_DIR/redirect_candidates.txt") found"

# ─────────────────────────────────────────────────────────────────────
section "Nuclei — Vulnerability & Misconfiguration Scanning"

NUCLEI_TARGETS="$OUTPUT_DIR/nuclei_targets.txt"
cat "$OUTPUT_DIR/alive_subdomains.txt" "$OUTPUT_DIR/alive_ports.txt" 2>/dev/null \
    | awk '{print $1}' | sort -u > "$NUCLEI_TARGETS"

if [ -s "$NUCLEI_TARGETS" ]; then
    NUCLEI_COUNT_TARGETS=$(count "$NUCLEI_TARGETS")
    echo -e "${YELLOW}  [~] Running Nuclei against $NUCLEI_COUNT_TARGETS targets...${NC}"

    nuclei -l "$NUCLEI_TARGETS" \
        -severity critical,high,medium,low,info \
        -silent \
        -stats \
        -rate-limit 150 \
        -c 25 \
        -o "$OUTPUT_DIR/nuclei_results.txt" \
        2>/dev/null || true

    NUCLEI_COUNT=$(count "$OUTPUT_DIR/nuclei_results.txt")
    echo -e "${GREEN}  [✓] Nuclei: $NUCLEI_COUNT findings${NC}"

    CRIT=$(grep -ci '\[critical\]' "$OUTPUT_DIR/nuclei_results.txt" 2>/dev/null || echo 0)
    HIGH=$(grep -ci '\[high\]'     "$OUTPUT_DIR/nuclei_results.txt" 2>/dev/null || echo 0)
    MED=$(grep -ci  '\[medium\]'   "$OUTPUT_DIR/nuclei_results.txt" 2>/dev/null || echo 0)
    LOW=$(grep -ci  '\[low\]'      "$OUTPUT_DIR/nuclei_results.txt" 2>/dev/null || echo 0)
    INFO=$(grep -ci '\[info\]'     "$OUTPUT_DIR/nuclei_results.txt" 2>/dev/null || echo 0)

    notify_msg "🛡️ [Recon: $TARGET] Nuclei findings: $NUCLEI_COUNT (Critical:$CRIT High:$HIGH Medium:$MED Low:$LOW Info:$INFO)"
    discord_file "$OUTPUT_DIR/nuclei_results.txt" "🛡️ **[$TARGET] Nuclei Findings** — $NUCLEI_COUNT total (🔴 Crit:$CRIT 🟠 High:$HIGH 🟡 Med:$MED 🔵 Low:$LOW ⚪ Info:$INFO)"


    grep -Ei '\[(critical|high)\]' "$OUTPUT_DIR/nuclei_results.txt" > "$OUTPUT_DIR/nuclei_critical_high.txt" 2>/dev/null || true
    if [ -s "$OUTPUT_DIR/nuclei_critical_high.txt" ]; then
        discord_file "$OUTPUT_DIR/nuclei_critical_high.txt" "🚨 **[$TARGET] CRITICAL/HIGH Findings — Review ASAP**"
    fi
else
    echo -e "${YELLOW}  [~] No alive targets available for Nuclei — skipping.${NC}"
    NUCLEI_COUNT=0
fi

pad() { printf "%-8s" "$(count "$1")"; }

echo
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}                      ${GREEN}RECON SUMMARY${NC}                             ${BLUE}║${NC}"
echo -e "${BLUE}╠══════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC}  Target              : ${YELLOW}$TARGET${NC}"
echo -e "${BLUE}║${NC}  Output Directory    : ${YELLOW}$OUTPUT_DIR${NC}"
echo -e "${BLUE}╠══════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}DISCOVERY${NC}                                                        ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Subdomains Found      : $(pad "$OUTPUT_DIR/resolved_subdomains.txt")                             ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Live Hosts            : $(pad "$OUTPUT_DIR/alive_subdomains.txt")                             ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Total URLs            : $(pad "$OUTPUT_DIR/all_urls.txt")                             ${BLUE}║${NC}"
echo -e "${BLUE}╠══════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}ENDPOINTS${NC}                                                        ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    API Endpoints         : $(pad "$OUTPUT_DIR/api_urls.txt")                             ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Auth Endpoints        : $(pad "$OUTPUT_DIR/auth_urls.txt")                             ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Registration Pages    : $(pad "$OUTPUT_DIR/registration_urls.txt")                             ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Password Reset Pages  : $(pad "$OUTPUT_DIR/password_urls.txt")                             ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Upload Features       : $(pad "$OUTPUT_DIR/upload_urls.txt")                             ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Admin Panels          : $(pad "$OUTPUT_DIR/admin_urls.txt")                             ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Payment Endpoints     : $(pad "$OUTPUT_DIR/payment_urls.txt")                             ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Account Endpoints     : $(pad "$OUTPUT_DIR/account_urls.txt")                             ${BLUE}║${NC}"
echo -e "${BLUE}╠══════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}SENSITIVE${NC}                                                        ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Documents             : $(pad "$OUTPUT_DIR/documents.txt")                             ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Sensitive Files       : $(pad "$OUTPUT_DIR/sensitive_files.txt")                             ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    JS Files              : $(pad "$OUTPUT_DIR/js_files.txt")                             ${BLUE}║${NC}"
echo -e "${BLUE}╠══════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}VULN CANDIDATES${NC}                                                  ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    SSRF Candidates       : $(pad "$OUTPUT_DIR/ssrf_candidates.txt")                             ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Redirect Candidates   : $(pad "$OUTPUT_DIR/redirect_candidates.txt")                             ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Nuclei Findings       : $(printf "%-8s" "$NUCLEI_COUNT")                             ${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo

DISCORD_SUMMARY="\`\`\`
╔══════════════════════════════════════════╗
║        RECON COMPLETE — $TARGET
╠══════════════════════════════════════════╣
║  DISCOVERY
║    Subdomains        : $(count "$OUTPUT_DIR/resolved_subdomains.txt")
║    Live Hosts        : $(count "$OUTPUT_DIR/alive_subdomains.txt")
║    Total URLs        : $(count "$OUTPUT_DIR/all_urls.txt")
╠══════════════════════════════════════════╣
║  ENDPOINTS
║    API               : $(count "$OUTPUT_DIR/api_urls.txt")
║    Auth              : $(count "$OUTPUT_DIR/auth_urls.txt")
║    Registration      : $(count "$OUTPUT_DIR/registration_urls.txt")
║    Password Reset    : $(count "$OUTPUT_DIR/password_urls.txt")
║    Upload            : $(count "$OUTPUT_DIR/upload_urls.txt")
║    Admin Panels      : $(count "$OUTPUT_DIR/admin_urls.txt")
║    Payment           : $(count "$OUTPUT_DIR/payment_urls.txt")
║    Account           : $(count "$OUTPUT_DIR/account_urls.txt")
╠══════════════════════════════════════════╣
║  SENSITIVE
║    Documents         : $(count "$OUTPUT_DIR/documents.txt")
║    Sensitive Files   : $(count "$OUTPUT_DIR/sensitive_files.txt")
║    JS Files          : $(count "$OUTPUT_DIR/js_files.txt")
╠══════════════════════════════════════════╣
║  VULN CANDIDATES
║    SSRF              : $(count "$OUTPUT_DIR/ssrf_candidates.txt")
║    Open Redirects    : $(count "$OUTPUT_DIR/redirect_candidates.txt")
║    Nuclei Findings   : $NUCLEI_COUNT
╠══════════════════════════════════════════╣
║  Finished : $(date '+%Y-%m-%d %H:%M:%S')
╚══════════════════════════════════════════╝
\`\`\`"

notify_msg "$DISCORD_SUMMARY"

echo -e "${GREEN}  [✓] All results sent to Discord.${NC}"

discord_msg "✅ **Recon Complete** | Target: \`$TARGET\` | $(date '+%Y-%m-%d %H:%M:%S')"
