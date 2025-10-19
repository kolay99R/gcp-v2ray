#!/bin/bash
set -euo pipefail

# ===== Colors =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# ===== Validators =====
validate_uuid() {
    local uuid_pattern='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    [[ $1 =~ $uuid_pattern ]] || { error "Invalid UUID format: $1"; return 1; }
}

validate_bot_token() {
    local token_pattern='^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$'
    [[ $1 =~ $token_pattern ]] || { error "Invalid Telegram Bot Token format"; return 1; }
}

validate_channel_id() { [[ $1 =~ ^-?[0-9]+$ ]] || { error "Invalid Channel ID"; return 1; } }
validate_chat_id() { [[ $1 =~ ^-?[0-9]+$ ]] || { error "Invalid Chat ID"; return 1; } }

validate_url() {
    local url="$1"
    local url_pattern='^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/[a-zA-Z0-9.~:/?#@!$&'"'"'()+,;=-]*)?$'
    local telegram_pattern='^https?://t.me/[a-zA-Z0-9_]+$'
    [[ "$url" =~ $telegram_pattern || "$url" =~ $url_pattern ]] || { error "Invalid URL: $url"; return 1; }
}

# ===== CPU & Memory selection =====
select_cpu() {
    echo; info "=== CPU Configuration ==="
    echo "1. 1 CPU Core (Default)"
    echo "2. 2 CPU Cores"
    echo "3. 4 CPU Cores"
    echo "4. 8 CPU Cores"
    while true; do
        read -p "Select CPU (1-4): " cpu_choice
        case $cpu_choice in
            1) CPU="1"; break;;
            2) CPU="2"; break;;
            3) CPU="4"; break;;
            4) CPU="8"; break;;
            *) echo "Invalid selection (1-4)";;
        esac
    done
    info "Selected CPU: $CPU core(s)"
}

select_memory() {
    echo; info "=== Memory Configuration ==="
    echo "1. 512Mi"
    echo "2. 1Gi"
    echo "3. 2Gi"
    echo "4. 4Gi"
    echo "5. 8Gi"
    echo "6. 16Gi"
    while true; do
        read -p "Select memory (1-6): " memory_choice
        case $memory_choice in
            1) MEMORY="512Mi"; break;;
            2) MEMORY="1Gi"; break;;
            3) MEMORY="2Gi"; break;;
            4) MEMORY="4Gi"; break;;
            5) MEMORY="8Gi"; break;;
            6) MEMORY="16Gi"; break;;
            *) echo "Invalid (1-6)";;
        esac
    done
    info "Selected Memory: $MEMORY"
}

select_region() {
    echo
    info "=== Region Selection ==="
    echo "
1. us-central1 (Iowa, USA 🇺🇸)
2. us-west1 (Oregon, USA 🇺🇸)
3. us-east1 (South Carolina, USA 🇺🇸)
4. europe-west1 (Belgium 🇧🇪)
5. asia-southeast1 (Singapore 🇸🇬)
6. asia-southeast2 (Indonesia 🇮🇩)
7. asia-northeast1 (Tokyo, Japan 🇯🇵)
8. asia-east1 (Taiwan 🇹🇼)
"
    while true; do
        read -p "Select region (1-8): " region_choice
        case $region_choice in
            1) REGION="us-central1"; break;;
            2) REGION="us-west1"; break;;
            3) REGION="us-east1"; break;;
            4) REGION="europe-west1"; break;;
            5) REGION="asia-southeast1"; break;;
            6) REGION="asia-southeast2"; break;;
            7) REGION="asia-northeast1"; break;;
            8) REGION="asia-east1"; break;;
            *) echo "Invalid (1-8)";;
        esac
    done
    info "Selected region: $REGION"
}

# ===== Telegram configuration =====
select_telegram_destination() {
    echo; info "=== Telegram Destination ==="
    echo "1. Channel"
    echo "2. Bot"
    echo "3. Both"
    echo "4. None"
    while true; do
        read -p "Select destination (1-4): " telegram_choice
        case $telegram_choice in
            1) TELEGRAM_DESTINATION="channel"; break;;
            2) TELEGRAM_DESTINATION="bot"; break;;
            3) TELEGRAM_DESTINATION="both"; break;;
            4) TELEGRAM_DESTINATION="none"; break;;
            *) echo "Invalid (1-4)";;
        esac
    done
}

get_channel_url() {
    echo; info "=== Channel Configuration ==="
    echo "Default URL: https://t.me/trenzych"
    while true; do
        read -p "Enter Channel URL [default: https://t.me/trenzych]: " CHANNEL_URL
        CHANNEL_URL=${CHANNEL_URL:-"https://t.me/trenzych"}
        CHANNEL_URL=$(echo "$CHANNEL_URL" | sed 's|/*$||')
        validate_url "$CHANNEL_URL" && break
    done
    read -p "Enter Channel Name [default: TRENZYCH]: " CHANNEL_NAME
    CHANNEL_NAME=${CHANNEL_NAME:-"TRENZYCH"}
}

get_telegram_ids() {
    if [[ "$TELEGRAM_DESTINATION" == "bot" || "$TELEGRAM_DESTINATION" == "both" ]]; then
        while true; do
            read -p "Enter Telegram Chat ID (bot): " TELEGRAM_CHAT_ID
            validate_chat_id "$TELEGRAM_CHAT_ID" && break
        done
    fi
    if [[ "$TELEGRAM_DESTINATION" == "channel" || "$TELEGRAM_DESTINATION" == "both" ]]; then
        while true; do
            read -p "Enter Telegram Channel ID (number with -100 prefix): " TELEGRAM_CHANNEL_ID
            validate_channel_id "$TELEGRAM_CHANNEL_ID" && break
        done
    fi
}

# ===== User input =====
get_user_input() {
    echo; info "=== Service Configuration ==="
    while true; do read -p "Enter service name: " SERVICE_NAME; [[ -n "$SERVICE_NAME" ]] && break; done
    while true; do read -p "Enter UUID [default: 9c910024-714e-4221-81c6-41ca9856e7ab]: " UUID
        UUID=${UUID:-"9c910024-714e-4221-81c6-41ca9856e7ab"}
        validate_uuid "$UUID" && break
    done
    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        while true; do read -p "Enter Telegram Bot Token: " TELEGRAM_BOT_TOKEN; validate_bot_token "$TELEGRAM_BOT_TOKEN" && break; done
    fi
    read -p "Enter host domain [default: m.googleapis.com]: " HOST_DOMAIN
    HOST_DOMAIN=${HOST_DOMAIN:-"m.googleapis.com"}
    [[ "$TELEGRAM_DESTINATION" != "none" ]] && get_channel_url
    [[ "$TELEGRAM_DESTINATION" != "none" ]] && get_telegram_ids
}

# ===== Project ID =====
check_or_select_project() {
    echo; info "=== GCP Project Configuration ==="
    while true; do
        read -p "Enter GCP Project ID: " PROJECT_ID
        [[ -n "$PROJECT_ID" ]] && break || echo "Project ID cannot be empty."
    done
    log "Using GCP project: $PROJECT_ID"
}

# ===== Deployment Preview & Command Print =====
prepare_deployment() {
    START_TIME=$(TZ='Asia/Yangon' date +"%d-%m-%Y (%I:%M %p)")
    END_TIME=$(TZ='Asia/Yangon' date -d "+5 hours" +"%d-%m-%Y (%I:%M %p)")

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    info "💡 Deployment preview:"
    echo -e "Project: ${YELLOW}${PROJECT_ID}${NC}"
    echo -e "Service: ${YELLOW}${SERVICE_NAME}${NC}"
    echo -e "Region: ${YELLOW}${REGION}${NC}"
    echo -e "CPU | Memory: ${YELLOW}${CPU} CPU | ${MEMORY}${NC}"
    echo -e "Domain: ${YELLOW}${HOST_DOMAIN}${NC}"
    echo -e "Start: ${YELLOW}${START_TIME}${NC}"
    echo -e "End:   ${YELLOW}${END_TIME}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    read -rp "Continue? (y/n) [default: y]: " CONFIRM
    CONFIRM=${CONFIRM:-y}
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Deployment canceled"; exit 0; }

    # ===== Print ready-to-run commands =====
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    info "⚠️ Cloud Run cannot run 'gcloud' inside the container."
    info "Copy and paste the following commands in Cloud Shell or local terminal to deploy:"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    echo -e "${YELLOW}# Enable required services${NC}"
    echo "gcloud services enable cloudbuild.googleapis.com run.googleapis.com iam.googleapis.com --quiet"

    echo -e "${YELLOW}# Clone repository${NC}"
    echo "[[ -d \"gcp-v2ray\" ]] && rm -rf gcp-v2ray"
    echo "git clone https://github.com/kolay99R/gcp-v2ray.git"
    echo "cd gcp-v2ray"

    echo -e "${YELLOW}# Deploy Cloud Run service${NC}"
    echo "gcloud run deploy ${SERVICE_NAME} \\"
    echo "    --image gcr.io/${PROJECT_ID}/gcp-v2ray-image \\"
    echo "    --platform managed \\"
    echo "    --region ${REGION} \\"
    echo "    --allow-unauthenticated \\"
    echo "    --cpu ${CPU} \\"
    echo "    --memory ${MEMORY} \\"
    echo "    --quiet"

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    info "✅ Deployment commands ready. Run them in Cloud Shell or local terminal."
}

# ===== Main =====
main() {
    info "=== GCP Cloud Run V2Ray Deployment ==="
    select_region
    select_cpu
    select_memory
    select_telegram_destination
    get_user_input
    check_or_select_project
    prepare_deployment
}

main "$@"
