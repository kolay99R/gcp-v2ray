#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Function to validate UUID format
validate_uuid() {
    local uuid_pattern='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    [[ $1 =~ $uuid_pattern ]] || { error "Invalid UUID format: $1"; return 1; }
}

# Function to validate Telegram Bot Token
validate_bot_token() {
    local token_pattern='^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$'
    [[ $1 =~ $token_pattern ]] || { error "Invalid Telegram Bot Token format"; return 1; }
}

# Function to validate Channel ID
validate_channel_id() { [[ $1 =~ ^-?[0-9]+$ ]] || { error "Invalid Channel ID"; return 1; }; }

# Function to validate Chat ID
validate_chat_id() { [[ $1 =~ ^-?[0-9]+$ ]] || { error "Invalid Chat ID"; return 1; }; }

# Function to validate URL
validate_url() {
    local url="$1"
    local url_pattern='^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/[a-zA-Z0-9._~:/?#[\]@!$&'"'"'()*+,;=-]*)?$'
    local telegram_pattern='^https?://t\.me/[a-zA-Z0-9_]+$'
    if [[ "$url" =~ $telegram_pattern ]] || [[ "$url" =~ $url_pattern ]]; then
        return 0
    else
        error "Invalid URL: $url"; return 1
    fi
}

# CPU selection
select_cpu() {
    echo; info "=== CPU Configuration ==="
    echo "1. 1 CPU Core (Default)"; echo "2. 2 CPU Cores"; echo "3. 4 CPU Cores"; echo "4. 8 CPU Cores"
    while true; do
        read -p "Select CPU (1-4): " cpu_choice
        case $cpu_choice in
            1) CPU="1"; break;; 2) CPU="2"; break;; 3) CPU="4"; break;; 4) CPU="8"; break;;
            *) echo "Invalid selection 1-4";;
        esac
    done
    info "Selected CPU: $CPU core(s)"
}

# Memory selection
select_memory() {
    echo; info "=== Memory Configuration ==="
    echo "Memory Options: 1.512Mi 2.1Gi 3.2Gi 4.4Gi 5.8Gi 6.16Gi"
    while true; do
        read -p "Select memory (1-6): " memory_choice
        case $memory_choice in
            1) MEMORY="512Mi"; break;; 2) MEMORY="1Gi"; break;; 3) MEMORY="2Gi"; break;;
            4) MEMORY="4Gi"; break;; 5) MEMORY="8Gi"; break;; 6) MEMORY="16Gi"; break;;
            *) echo "Invalid 1-6";;
        esac
    done
    info "Selected Memory: $MEMORY"
}

# Region selection
select_region() {
    echo; info "=== Region Selection ==="
    echo "1.us-central1 2.us-west1 3.us-east1 4.europe-west1 5.asia-southeast1 6.asia-southeast2 7.asia-northeast1 8.asia-east1"
    while true; do
        read -p "Select region (1-8): " region_choice
        case $region_choice in
            1) REGION="us-central1"; break;; 2) REGION="us-west1"; break;; 3) REGION="us-east1"; break;;
            4) REGION="europe-west1"; break;; 5) REGION="asia-southeast1"; break;; 6) REGION="asia-southeast2"; break;;
            7) REGION="asia-northeast1"; break;; 8) REGION="asia-east1"; break;;
            *) echo "Invalid 1-8";;
        esac
    done
    info "Selected region: $REGION"
}

# Telegram destination
select_telegram_destination() {
    echo; info "=== Telegram Destination ==="
    echo "1.Channel 2.Bot 3.Both 4.None"
    while true; do
        read -p "Select destination (1-4): " telegram_choice
        case $telegram_choice in
            1) TELEGRAM_DESTINATION="channel"; break;;
            2) TELEGRAM_DESTINATION="bot"; break;;
            3) TELEGRAM_DESTINATION="both"; break;;
            4) TELEGRAM_DESTINATION="none"; break;;
            *) echo "Invalid 1-4";;
        esac
    done
}

# Channel URL input
get_channel_url() {
    echo; info "=== Channel Configuration ==="
    echo "Default URL: https://t.me/trenzych"
    while true; do
        read -p "Enter Channel URL [default: https://t.me/trenzych]: " CHANNEL_URL
        CHANNEL_URL=${CHANNEL_URL:-"https://t.me/trenzych"}
        CHANNEL_URL=$(echo "$CHANNEL_URL" | sed 's|/*$||')
        validate_url "$CHANNEL_URL" && break
    done
    read -p "Enter Channel Name [default:TRENZYCH]: " CHANNEL_NAME
    CHANNEL_NAME=${CHANNEL_NAME:-"TRENZYCH"}
}

# User input
get_user_input() {
    echo; info "=== Service Configuration ==="
    while true; do read -p "Enter service name: " SERVICE_NAME; [[ -n "$SERVICE_NAME" ]] && break; done
    while true; do read -p "Enter UUID: " UUID; UUID=${UUID:-"9c910024-714e-4221-81c6-41ca9856e7ab"}; validate_uuid "$UUID" && break; done
    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        while true; do read -p "Enter Telegram Bot Token: " TELEGRAM_BOT_TOKEN; validate_bot_token "$TELEGRAM_BOT_TOKEN" && break; done
    fi
    read -p "Enter host domain [default: m.googleapis.com]: " HOST_DOMAIN; HOST_DOMAIN=${HOST_DOMAIN:-"m.googleapis.com"}
    [[ "$TELEGRAM_DESTINATION" != "none" ]] && get_channel_url
}

# Deployment notification
send_to_telegram() {
    local chat_id="$1"; local message="$2"
    local keyboard=$(cat <<EOF
{"inline_keyboard":[[{"text":"$CHANNEL_NAME","url":"$CHANNEL_URL"}]]}
EOF
)
    response=$(curl -s -w "%{http_code}" -X POST -H "Content-Type: application/json" \
        -d "{\"chat_id\":\"${chat_id}\",\"text\":\"$message\",\"parse_mode\":\"HTML\",\"disable_web_page_preview\":true,\"reply_markup\":$keyboard}" \
        https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage)
    [[ "${response: -3}" == "200" ]] || { error "Telegram send failed: ${response}"; return 1; }
}

# Main function
main() {
    info "=== GCP Cloud Run V2Ray Deployment ==="
    select_region; select_cpu; select_memory; select_telegram_destination; get_user_input
    
    PROJECT_ID=$(gcloud config get-value project)
    
    log "Starting deployment..."
    
    # Time
    START_TIME=$(TZ='Asia/Yangon' date +"%d-%m-%Y (%I:%M %p)")
    END_TIME=$(TZ='Asia/Yangon' date -d "+5 hours" +"%d-%m-%Y (%I:%M %p)")
    
    # VLESS link
    SERVICE_URL="example.com" # placeholder, replace with actual after deployment
    DOMAIN=$(echo $SERVICE_URL | sed 's|https://||')
    VLESS_LINK="vless://${UUID}@${HOST_DOMAIN}:443?path=%2Ftg-%40trenzych&security=tls&alpn=h3%2Ch2%2Chttp%2F1.1&encryption=none&host=${DOMAIN}&fp=randomized&type=ws&sni=${DOMAIN}#${SERVICE_NAME}"
    
    # Telegram HTML message
    MESSAGE=$(cat <<EOF
<b>MYTEL GCP VLESS DEPLOYMENT</b>
━━━━━━━━━━━━━━━━━━━━
<blockquote>
<b>• Service:</b> ${SERVICE_NAME}
<b>• Region:</b> ${REGION}
<b>• Resource:</b> ${CPU} CPU | ${MEMORY} RAM
<b>• Domain:</b> ${DOMAIN}

<b>• Start:</b> ${START_TIME}
<b>• End:</b> ${END_TIME}
</blockquote>
━━━━━━━━━━━━━━━━━━━━
<b>V2Ray Configuration Access Key</b>
━━━━━━━━━━━━━━━━━━━━
<code>${VLESS_LINK}</code>
<i>Usage: Copy the above link and import to your V2Ray client App</i>
EOF
)
    
    echo "$MESSAGE" > deployment-info.txt
    info "Deployment info saved to deployment-info.txt"
    
    [[ "$TELEGRAM_DESTINATION" != "none" ]] && send_to_telegram "${TELEGRAM_CHAT_ID:-$TELEGRAM_CHANNEL_ID}" "$MESSAGE"
    
    log "Deployment completed!"
}

main "$@"
