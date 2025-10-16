#!/bin/bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Validation functions
validate_uuid() {
    local pattern='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    [[ $1 =~ $pattern ]] || { error "Invalid UUID: $1"; return 1; }
}
validate_bot_token() {
    local pattern='^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$'
    [[ $1 =~ $pattern ]] || { error "Invalid Telegram Bot Token"; return 1; }
}
validate_channel_id() { [[ $1 =~ ^-?[0-9]+$ ]] || { error "Invalid Channel ID"; return 1; } }
validate_chat_id() { [[ $1 =~ ^-?[0-9]+$ ]] || { error "Invalid Chat ID"; return 1; } }

# CPU selection
select_cpu() {
    info "=== CPU Configuration ==="
    echo "1. 1 CPU Core (Default)"; echo "2. 2 CPU Cores"; echo "3. 4 CPU Cores"; echo "4. 8 CPU Cores"
    while true; do
        read -p "Select CPU cores (1-4): " cpu_choice
        case $cpu_choice in
            1) CPU="1"; break ;;
            2) CPU="2"; break ;;
            3) CPU="4"; break ;;
            4) CPU="8"; break ;;
            *) echo "Invalid selection." ;;
        esac
    done
    info "Selected CPU: $CPU"
}

# Memory selection
select_memory() {
    info "=== Memory Configuration ==="
    echo "Memory Options: 1)512Mi 2)1Gi 3)2Gi 4)4Gi 5)8Gi 6)16Gi"
    while true; do
        read -p "Select memory (1-6): " m
        case $m in
            1) MEMORY="512Mi"; break ;;
            2) MEMORY="1Gi"; break ;;
            3) MEMORY="2Gi"; break ;;
            4) MEMORY="4Gi"; break ;;
            5) MEMORY="8Gi"; break ;;
            6) MEMORY="16Gi"; break ;;
            *) echo "Invalid selection." ;;
        esac
    done
    info "Selected Memory: $MEMORY"
}

# Region selection
select_region() {
    info "=== Region Selection ==="
    echo "1) us-central1 2) us-west1 3) us-east1 4) europe-west1 5) asia-southeast1 6) asia-northeast1 7) asia-east1"
    while true; do
        read -p "Select region (1-7): " r
        case $r in
            1) REGION="us-central1"; break ;;
            2) REGION="us-west1"; break ;;
            3) REGION="us-east1"; break ;;
            4) REGION="europe-west1"; break ;;
            5) REGION="asia-southeast1"; break ;;
            6) REGION="asia-northeast1"; break ;;
            7) REGION="asia-east1"; break ;;
            *) echo "Invalid selection." ;;
        esac
    done
    info "Selected region: $REGION"
}

# Telegram destination
select_telegram_destination() {
    info "=== Telegram Destination ==="
    echo "1) Channel 2) Bot PM 3) Both 4) None"
    while true; do
        read -p "Select (1-4): " t
        case $t in
            1) TELEGRAM_DESTINATION="channel"; 
               while true; do read -p "Channel ID: " TELEGRAM_CHANNEL_ID; validate_channel_id "$TELEGRAM_CHANNEL_ID" && break; done; break ;;
            2) TELEGRAM_DESTINATION="bot";
               while true; do read -p "Chat ID: " TELEGRAM_CHAT_ID; validate_chat_id "$TELEGRAM_CHAT_ID" && break; done; break ;;
            3) TELEGRAM_DESTINATION="both";
               while true; do read -p "Channel ID: " TELEGRAM_CHANNEL_ID; validate_channel_id "$TELEGRAM_CHANNEL_ID" && break; done
               while true; do read -p "Chat ID: " TELEGRAM_CHAT_ID; validate_chat_id "$TELEGRAM_CHAT_ID" && break; done; break ;;
            4) TELEGRAM_DESTINATION="none"; break ;;
            *) echo "Invalid selection." ;;
        esac
    done
}

# User input
get_user_input() {
    info "=== Service Configuration ==="
    while true; do read -p "Service name: " SERVICE_NAME; [[ -n "$SERVICE_NAME" ]] && break; done
    while true; do read -p "UUID: " UUID; UUID=${UUID:-"9c910024-714e-4221-81c6-41ca9856e7ab"}; validate_uuid "$UUID" && break; done
    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        while true; do read -p "Telegram Bot Token: " TELEGRAM_BOT_TOKEN; validate_bot_token "$TELEGRAM_BOT_TOKEN" && break; done
    fi
    read -p "Host domain [default=SERVICE_URL]: " HOST_DOMAIN
    HOST_DOMAIN=${HOST_DOMAIN:-""}
}

# Prerequisite validation
validate_prerequisites() {
    log "Validating prerequisites..."
    command -v gcloud >/dev/null || { error "gcloud not installed"; exit 1; }
    command -v git >/dev/null || { error "git not installed"; exit 1; }
    PROJECT_ID=$(gcloud config get-value project)
    [[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || { error "No project set"; exit 1; }
}

# Cleanup
cleanup() { [[ -d "gcp-v2ray" ]] && rm -rf gcp-v2ray; }

# Telegram helper
escape_md2() { echo "$1" | sed -e 's/\\/\\\\/g' -e 's/_/\\_/g' -e 's/\*/\\*/g' -e 's//\/g' -e 's//\/g' -e 's/(/\/g' -e 's/)/\/g' -e 's/>/\\>/g' -e 's/`/\\`/g'; }
send_to_telegram() {
    local chat_id="$1"; local message="$2"
    local response=$(curl -s -w "%{http_code}" -X POST -H "Content-Type: application/json" \
      -d "{\"chat_id\":\"$chat_id\",\"text\":\"$message\",\"parse_mode\":\"MarkdownV2\",\"disable_web_page_preview\":true}" \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage")
    [[ "${response: -3}" == "200" ]] || { error "Telegram send failed"; return 1; }
}

send_deployment_notification() {
    local msg=$(escape_md2 "$1"); local success=0
    case $TELEGRAM_DESTINATION in
        channel) send_to_telegram "$TELEGRAM_CHANNEL_ID" "$msg" && ((success++)) ;;
        bot) send_to_telegram "$TELEGRAM_CHAT_ID" "$msg" && ((success++)) ;;
        both) send_to_telegram "$TELEGRAM_CHANNEL_ID" "$msg" && ((success++)); send_to_telegram "$TELEGRAM_CHAT_ID" "$msg" && ((success++)) ;;
        none) log "Skipping Telegram notification"; return 0 ;;
    esac
    [[ $success -gt 0 ]] || warn "All Telegram notifications failed"
}

# Main
main() {
    info "=== GCP Cloud Run V2Ray Deployment ==="
    select_region; select_cpu; select_memory; select_telegram_destination; get_user_input
    validate_prerequisites
    trap cleanup EXIT

    log "Enabling APIs..."
    gcloud services enable cloudbuild.googleapis.com run.googleapis.com iam.googleapis.com --quiet
    cleanup

    log "Cloning repository..."
    git clone https://github.com/andrewzinkyaw/gcp-v2ray.git
    cd gcp-v2ray

    log "Building container..."
    gcloud builds submit --tag gcr.io/${PROJECT_ID}/gcp-v2ray-image --quiet

    log "Deploying to Cloud Run..."
    gcloud run deploy ${SERVICE_NAME} \
        --image gcr.io/${PROJECT_ID}/gcp-v2ray-image \
        --platform managed \
        --region ${REGION} \
        --allow-unauthenticated \
        --cpu ${CPU} \
        --memory ${MEMORY} \
        --quiet

    SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} --region ${REGION} --format 'value(status.url)' --quiet)
    DOMAIN=$(echo $SERVICE_URL | sed 's|https://||; s|/$||')
    HOST_DOMAIN=${HOST_DOMAIN:-$DOMAIN}

    # Date
    START_TIME=$(TZ='Asia/Yangon' date +"%Y-%m-%d %H:%M:%S")
    END_TIME=$(TZ='Asia/Yangon' date -d "+5 hours" +"%Y-%m-%d %H:%M:%S") # GNU date

    VLESS_LINK="vless://${UUID}@${HOST_DOMAIN}:443?path=%2Ftg-%40trenzych&security=tls&alpn=h3%2Ch2%2Chttp%2F1.1&encryption=none&host=${DOMAIN}&fp=randomized&type=ws&sni=${DOMAIN}#${SERVICE_NAME}"

    MESSAGE="> *GCP VLESS Deployment Success*\n\`\`\`\n• Service: ${SERVICE_NAME}\n• Region: ${REGION}\n• Resources: ${CPU} CPU | ${MEMORY} RAM\n• Domain: ${DOMAIN}\n• Start: ${START_TIME}\n• End: ${END_TIME}\n\`\`\`\n> *V2Ray Access Link*\n\`\`\`\n${VLESS_LINK}\n\`\`\`"

    CONSOLE_MESSAGE="GCP VLESS Deployment → Success ✅\nService: ${SERVICE_NAME}\nRegion: ${REGION}\nResources: ${CPU} CPU | ${MEMORY} RAM\nDomain: ${DOMAIN}\nStart: ${START_TIME}\nEnd: ${END_TIME}\n\nV2Ray Link:\n${VLESS_LINK}"

    echo "$CONSOLE_MESSAGE" > deployment-info.txt
    log "Deployment info saved to deployment-info.txt"
    echo "$CONSOLE_MESSAGE"

    [[ "$TELEGRAM_DESTINATION" != "none" ]] && send_deployment_notification "$MESSAGE"

    log "Deployment completed successfully! Service URL: $SERVICE_URL"
}

main "$@"
