#!/bin/bash

TARGET=$1
OUTPUT_DIR="recon_$TARGET"
mkdir -p "$OUTPUT_DIR"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

#PUT YOUR DISCORD WEBHOOK URL HERE 
DISCORD_WEBHOOK="https://discord.com/api/webhooks/XXXXXXX"


section() {
    echo
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  [+] $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
}

count() { [ -f "$1" ] && wc -l < "$1" || echo 0; }

notify_msg() {
    echo "$1" | notify -provider discord -id recon-alerts -silent 2>/dev/null
}


discord_file() {
    local file="$1"
    local msg="$2"
    if [ -f "$file" ] && [ -s "$file" ]; then
        curl -s -X POST "$DISCORD_WEBHOOK" \
            -F "content=$msg" \
            -F "file=@$file" > /dev/null
        echo -e "${GREEN}  [✓] Sent to Discord: $(basename "$file")${NC}"
    else
        echo -e "${YELLOW}  [~] Skipped (empty): $(basename "$file")${NC}"
    fi
}


discord_msg() {
    curl -s -X POST "$DISCORD_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "{\"content\": \"$1\"}" > /dev/null
}

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
cat "$OUTPUT_DIR/subs.txt" | alterx -o "$OUTPUT_DIR/subdomains.txt"

if [ ! -f "$OUTPUT_DIR/subdomains.txt" ]; then
    echo -e "${RED}[!] subdomains.txt not found — subenum/alterx failed.${NC}"
    discord_msg "❌ **Recon Failed** | Target: \`$TARGET\` | subenum/alterx produced no output."
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────
section "DnsX — DNS Resolution"
dnsx -l "$OUTPUT_DIR/subdomains.txt" -o "$OUTPUT_DIR/dnsx_resolved.txt"

# ─────────────────────────────────────────────────────────────────────
section "ShuffleDNS — Bruteforce Resolution"
shuffledns -list "$OUTPUT_DIR/subdomains.txt" \
    -r /home/cypherx/payloads/resolvers.txt \
    -o "$OUTPUT_DIR/shuffledns_subs.txt"


cat "$OUTPUT_DIR/dnsx_resolved.txt" "$OUTPUT_DIR/shuffledns_subs.txt" \
    | sort -u > "$OUTPUT_DIR/resolved_subdomains.txt"

if [ ! -f "$OUTPUT_DIR/resolved_subdomains.txt" ]; then
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

if [ ! -f "$OUTPUT_DIR/alive_subdomains.txt" ]; then
    echo -e "${RED}[!] alive_subdomains.txt not found — httpx failed.${NC}"
    discord_msg "❌ **HttpX Failed** | Target: \`$TARGET\`"
    exit 1
fi

ALIVE_COUNT=$(count "$OUTPUT_DIR/alive_subdomains.txt")
echo -e "${GREEN}  [✓] Found $ALIVE_COUNT alive hosts${NC}"


notify_msg "✅ [Recon: $TARGET] Live hosts: $ALIVE_COUNT"
discord_file "$OUTPUT_DIR/alive_subdomains.txt" "🟢 **[$TARGET] Alive Hosts** — $ALIVE_COUNT live (with status codes + tech)"

# ─────────────────────────────────────────────────────────────────────
section "Gowitness — Screenshots"

GOWITNESS_DIR="$OUTPUT_DIR/gowitness"
GOWITNESS_SHOTS="$GOWITNESS_DIR/screenshots"
mkdir -p "$GOWITNESS_SHOTS"


awk '{print $1}' "$OUTPUT_DIR/alive_subdomains.txt" > "$GOWITNESS_DIR/gowitness_targets.txt"

gowitness scan file \
    -f "$GOWITNESS_DIR/gowitness_targets.txt" \
    -s "$GOWITNESS_SHOTS" \
    --write-none \
    --threads 10 \
    --timeout 30 \
    --delay 2 \
    --screenshot-format jpeg \
    --screenshot-jpeg-quality 80 \
    -q

SHOT_COUNT=$(find "$GOWITNESS_SHOTS" -name "*.jpeg" -o -name "*.png" 2>/dev/null | wc -l)
echo -e "${GREEN}  [✓] Captured $SHOT_COUNT screenshots${NC}"
notify_msg "📸 [Recon: $TARGET] Screenshots done: $SHOT_COUNT captured"


section "Sending Screenshots to Discord"

discord_msg "📸 **[$TARGET] Gowitness Screenshots** — $SHOT_COUNT total captured. Uploading top 20..."

SENT=0
MAX_SEND=20

find "$GOWITNESS_SHOTS" -type f \( -name "*.jpeg" -o -name "*.png" \) | head -n "$MAX_SEND" | while read -r screenshot; do
    filename=$(basename "$screenshot")
  
    label=$(echo "$filename" | sed 's/[_-]/ /g' | sed 's/\..*//')

    curl -s -X POST "$DISCORD_WEBHOOK" \
        -F "content=🖼️ \`$label\`" \
        -F "file=@$screenshot" > /dev/null

    SENT=$((SENT + 1))
    echo -e "${GREEN}  [✓] Sent screenshot $SENT/$MAX_SEND: $filename${NC}"

    sleep 0.5
done


if [ "$SHOT_COUNT" -gt "$MAX_SEND" ]; then
    echo -e "${YELLOW}  [~] Zipping remaining screenshots...${NC}"
    REMAINING_ZIP="$GOWITNESS_DIR/screenshots_all.zip"
    zip -q -j "$REMAINING_ZIP" "$GOWITNESS_SHOTS"/*.jpeg "$GOWITNESS_SHOTS"/*.png 2>/dev/null
    discord_file "$REMAINING_ZIP" "📦 **[$TARGET] All $SHOT_COUNT Screenshots (ZIP)**"
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

echo -e "${YELLOW}  [~] Running Waymore (all providers, rate-limit safe)...${NC}"
waymore -i "$TARGET" \
    -mode U \
    --providers wayback,commoncrawl,otx,urlscan,virustotal \
    -oU "$OUTPUT_DIR/urls_waymore.txt" \
    -wrlr 3 \
    -urlr 2 \
    -p 2 \
    -t 30 \
    -r 3 \
    -m 50000 \
    -nd \
    2>/dev/null || true
echo -e "${GREEN}  [✓] Waymore: $(count "$OUTPUT_DIR/urls_waymore.txt") URLs${NC}"

echo -e "${YELLOW}  [~] Fetching OTX AlienVault...${NC}"
curl -s "https://otx.alienvault.com/api/v1/indicators/domain/$TARGET/url_list?limit=500&page=1" \
    | grep -oP '"url": *"\K[^"]+' \
    > "$OUTPUT_DIR/urls_otx.txt" 2>/dev/null || true
echo -e "${GREEN}  [✓] OTX: $(count "$OUTPUT_DIR/urls_otx.txt") URLs${NC}"


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
    "$OUTPUT_DIR/urls_waymore.txt" \
    "$OUTPUT_DIR/urls_otx.txt" \
    "$OUTPUT_DIR/urls_js_mined.txt" \
    2>/dev/null \
    | grep -Ei '^https?://' \
    | sed 's/#.*//' \
    | sort -u > "$OUTPUT_DIR/all_urls.txt"

URL_COUNT=$(count "$OUTPUT_DIR/all_urls.txt")

echo
echo -e "${BLUE}  ┌─ URL Sources Breakdown ─────────────────────────────┐${NC}"
echo -e "${BLUE}  │${NC}  GAU (Wayback+OTX+CC+URLScan) : $(printf "%-8s" $(count "$OUTPUT_DIR/urls_gau.txt"))              ${BLUE}│${NC}"
echo -e "${BLUE}  │${NC}  Katana (active crawl)        : $(printf "%-8s" $(count "$OUTPUT_DIR/urls_katana.txt"))              ${BLUE}│${NC}"
echo -e "${BLUE}  │${NC}  Waymore (WB+CC+OTX+US+VT)   : $(printf "%-8s" $(count "$OUTPUT_DIR/urls_waymore.txt"))              ${BLUE}│${NC}"
echo -e "${BLUE}  │${NC}  OTX AlienVault               : $(printf "%-8s" $(count "$OUTPUT_DIR/urls_otx.txt"))              ${BLUE}│${NC}"
echo -e "${BLUE}  │${NC}  JS File Mining               : $(printf "%-8s" $(count "$OUTPUT_DIR/urls_js_mined.txt"))              ${BLUE}│${NC}"
echo -e "${BLUE}  │${NC}  ─────────────────────────────────────────────  ${BLUE}│${NC}"
echo -e "${BLUE}  │${NC}  TOTAL UNIQUE                 : ${GREEN}$(printf "%-8s" $URL_COUNT)${NC}              ${BLUE}│${NC}"
echo -e "${BLUE}  └─────────────────────────────────────────────────────┘${NC}"

notify_msg "✅ [Recon: $TARGET] $URL_COUNT unique URLs — GAU+Katana+Waymore(WB+CC+OTX+URLScan+VT)+OTX+JSMining"

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
╠══════════════════════════════════════════╣
║  Finished : $(date '+%Y-%m-%d %H:%M:%S')
╚══════════════════════════════════════════╝
\`\`\`"

echo "$DISCORD_SUMMARY" | notify -provider discord -id recon-alerts -silent 2>/dev/null

echo -e "${GREEN}  [✓] All results sent to Discord.${NC}"