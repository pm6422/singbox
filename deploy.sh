#!/bin/bash

# Sing-box Server One-click Deployment Script
set -e

echo "=========================================="
echo "  Sing-box Server Automated Deployment"
echo "=========================================="

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Log functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Please run this script as root"
        exit 1
    fi
}

# Install Docker and Docker Compose
install_docker() {
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        log_info "Docker and Docker Compose are already installed"
        log_info "Docker version: $(docker --version)"
        log_info "Docker Compose version: $(docker compose version)"
        return
    fi

    log_info "Installing Docker..."
    curl -fsSL https://get.docker.com | bash

    # Start and enable Docker service
    systemctl start docker
    systemctl enable docker

    # Verify installation
    if docker --version &> /dev/null && docker compose version &> /dev/null; then
        log_info "Docker installed successfully: $(docker --version)"
        log_info "Docker Compose version: $(docker compose version)"
    else
        log_error "Docker installation failed"
        exit 1
    fi
}

# Create necessary directories and configurations
setup_configurations() {
    log_info "Setting up configuration directory..."
    mkdir -p config
    chmod 755 config

    # Ensure users.txt exists
    if [ ! -f "config/users.txt" ]; then
        log_info "users.txt not found. Creating default config/users.txt with 'pm6422' and 'chenxin'..."
        cat <<EOF > config/users.txt
pm6422
chenxin
EOF
    fi

    # Read users from users.txt
    USERS=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Trim whitespace
        clean_line=$(echo "$line" | xargs 2>/dev/null || echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [ -n "$clean_line" ] && [[ ! "$clean_line" =~ ^# ]]; then
            USERS+=("$clean_line")
        fi
    done < config/users.txt

    if [ ${#USERS[@]} -eq 0 ]; then
        log_error "No valid users found in config/users.txt. Please add at least one username."
        exit 1
    fi

    log_info "Detected ${#USERS[@]} users configured in config/users.txt."

    # Try to pull image first
    log_info "Pulling official Sing-box Docker image..."
    docker pull ghcr.io/sagernet/sing-box:latest

    # Try to reuse existing Reality keys if config.json and client_links.txt exist
    REUSED_KEYS=false
    PRIVATE_KEY=""
    PUBLIC_KEY=""
    SHORT_ID=""

    if [ -f "config/config.json" ] && [ -f "config/client_links.txt" ]; then
        log_info "Found existing config.json. Attempting to extract and reuse existing Reality keys..."
        
        # Extract private key
        EXISTING_PRIV=$(python3 -c "import json; print(json.load(open('config/config.json'))['inbounds'][0]['tls']['reality']['private_key'])" 2>/dev/null \
                       || python -c "import json; print(json.load(open('config/config.json'))['inbounds'][0]['tls']['reality']['private_key'])" 2>/dev/null \
                       || grep '"private_key"' config/config.json | head -n 1 | cut -d '"' -f 4 \
                       || echo "")
        
        # Extract short id
        EXISTING_SID=$(python3 -c "import json; print(json.load(open('config/config.json'))['inbounds'][0]['tls']['reality']['short_id'][0])" 2>/dev/null \
                       || python -c "import json; print(json.load(open('config/config.json'))['inbounds'][0]['tls']['reality']['short_id'][0])" 2>/dev/null \
                       || grep -A 1 '"short_id"' config/config.json | grep -v '"short_id"' | cut -d '"' -f 4 | tr -d ' ' \
                       || echo "")
        
        # Extract public key from client_links.txt
        EXISTING_PBK=$(grep -o "pbk=[^&]*" config/client_links.txt | head -n 1 | cut -d '=' -f 2 || echo "")

        if [ -n "$EXISTING_PRIV" ] && [ -n "$EXISTING_SID" ] && [ -n "$EXISTING_PBK" ]; then
            PRIVATE_KEY=$(echo "$EXISTING_PRIV" | tr -d '\r\n')
            PUBLIC_KEY=$(echo "$EXISTING_PBK" | tr -d '\r\n')
            SHORT_ID=$(echo "$EXISTING_SID" | tr -d '\r\n')
            REUSED_KEYS=true
            log_info "Successfully reused existing Reality credentials (short_id: $SHORT_ID)."
        else
            log_warn "Failed to extract some existing credentials. Generating new Reality keys..."
        fi
    fi

    # Generate new Reality keys if we couldn't reuse
    if [ "$REUSED_KEYS" = false ]; then
        log_info "Generating new Reality credentials..."
        KEYPAIR=$(docker run --rm ghcr.io/sagernet/sing-box:latest generate reality-keypair)
        PRIVATE_KEY=$(echo "$KEYPAIR" | awk '/PrivateKey/ {print $2}' | tr -d '\r\n')
        PUBLIC_KEY=$(echo "$KEYPAIR" | awk '/PublicKey/ {print $2}' | tr -d '\r\n')
        SHORT_ID=$(openssl rand -hex 8 | tr -d '\r\n')
    fi

    # Detect public IP
    log_info "Detecting server public IP..."
    SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org || curl -s --max-time 5 https://ifconfig.me || echo "")
    
    # Prompt user for domain (defaulting to public IP)
    echo -e "${YELLOW}------------------------------------------${NC}"
    if [ -n "$SERVER_IP" ]; then
        read -p "请输入您为此 Sing-box 服务绑定的域名 (直接回车将使用公网 IP: $SERVER_IP): " USER_DOMAIN
    else
        read -p "自动获取公网 IP 失败，请输入您的服务器域名或公网 IP: " USER_DOMAIN
    fi
    echo -e "${YELLOW}------------------------------------------${NC}"

    CONNECTION_ADDRESS=""
    if [ -n "$USER_DOMAIN" ]; then
        CONNECTION_ADDRESS=$(echo "$USER_DOMAIN" | tr -d '[:space:]')
        log_info "将使用自定义地址作为客户端连接目标: $CONNECTION_ADDRESS"
    else
        CONNECTION_ADDRESS="$SERVER_IP"
        if [ -z "$CONNECTION_ADDRESS" ]; then
            log_error "未输入且无法自动获取公网 IP，配置无法继续。"
            exit 1
        fi
        log_info "将使用检测到的公网 IP 作为客户端连接目标: $CONNECTION_ADDRESS"
    fi

    # Process each user
    USERS_JSON=""
    NEW_CLIENT_LINKS=""
    first=true

    for username in "${USERS[@]}"; do
        UUID=""
        # Try to find existing UUID for this username to keep client connection intact
        if [ -f "config/config.json" ]; then
            UUID=$(python3 -c "import json; config = json.load(open('config/config.json')); users = config['inbounds'][0]['users']; print(next((u['uuid'] for u in users if u['name'] == '$username'), ''))" 2>/dev/null \
                   || python -c "import json; config = json.load(open('config/config.json')); users = config['inbounds'][0]['users']; print(next((u['uuid'] for u in users if u['name'] == '$username'), ''))" 2>/dev/null \
                   || echo "")
            
            # Fallback to grep in case python extraction failed but user exists in client_links
            if [ -z "$UUID" ] && [ -f "config/client_links.txt" ]; then
                EXISTING_LINE=$(grep "^${username}: vless://" config/client_links.txt || echo "")
                if [ -n "$EXISTING_LINE" ]; then
                    UUID=$(echo "$EXISTING_LINE" | cut -d '/' -f 3 | cut -d '@' -f 1)
                fi
            fi
        fi

        if [ -n "$UUID" ]; then
            UUID=$(echo "$UUID" | tr -d '\r\n')
            log_info "User '$username': Reused existing UUID."
        else
            UUID=$(docker run --rm ghcr.io/sagernet/sing-box:latest generate uuid | tr -d '\r\n')
            log_info "User '$username': Generated a new UUID."
        fi

        # Build users array JSON
        if [ "$first" = true ]; then
            first=false
        else
            USERS_JSON="$USERS_JSON,"
        fi
        USERS_JSON="$USERS_JSON{\"name\": \"$username\", \"uuid\": \"$UUID\", \"flow\": \"xtls-rprx-vision\"}"

        # Generate client link using the connection address (domain or IP)
        LINK="vless://$UUID@$CONNECTION_ADDRESS:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&pbk=$PUBLIC_KEY&sid=$SHORT_ID#singbox-$username"
        NEW_CLIENT_LINKS="$NEW_CLIENT_LINKS${username}: ${LINK}"$'\n'
    done

    # Write config.json
    log_info "Writing server config.json..."
    cat <<EOF > config/config.json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": 443,
      "users": [
        $USERS_JSON
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.microsoft.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "www.microsoft.com",
            "server_port": 443
          },
          "private_key": "$PRIVATE_KEY",
          "short_id": [
            "$SHORT_ID"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ]
}
EOF

    # Save links
    echo -n "$NEW_CLIENT_LINKS" > config/client_links.txt
    log_info "Configurations prepared successfully."
}

# Deploy service via docker compose
deploy_service() {
    log_info "Starting service deployment..."

    # Validate docker-compose file
    if ! docker compose config -q; then
        log_error "Invalid docker-compose.yml file"
        exit 1
    fi

    # Check if sing-box container is already running
    if docker compose ps | grep -q "Up"; then
        log_info "Sing-box is already running. Applying configuration changes by restarting..."
        docker compose up -d --remove-orphans
        docker compose restart sing-box
    else
        log_info "Starting Sing-box container..."
        docker compose up -d
    fi

    # Wait for service initialization
    log_info "Waiting for service to start..."
    sleep 3

    # Check status
    if docker compose ps | grep -q "Up"; then
        log_info "Sing-box is running successfully."
    else
        log_error "Sing-box failed to start. Printing container logs:"
        docker compose logs --tail=30
        exit 1
    fi
}

# Show deployment information
show_info() {
    echo ""
    echo "=========================================="
    echo "          Deployment Complete!"
    echo "=========================================="
    echo "All configured users can now connect."
    echo ""
    echo -e "Server Port: ${GREEN}443 (TCP + UDP)${NC}"
    echo "Reality Camouflage Target: www.microsoft.com"
    echo ""
    echo "------------------------------------------"
    echo "            Client VLESS Links            "
    echo "------------------------------------------"
    echo "Copy and paste the links below into your client application:"
    echo ""

    if [ -f "config/client_links.txt" ]; then
        # Output stored links in color
        while IFS= read -r line; do
            user_name=$(echo "$line" | cut -d ':' -f 1)
            link_url=$(echo "$line" | cut -d ' ' -f 2-)
            echo -e "${YELLOW}[User: $user_name]${NC}"
            echo -e "${GREEN}$link_url${NC}"
            echo ""
        done < config/client_links.txt
    else
        log_warn "Client links file not found. Check config/config.json."
    fi

    echo "=========================================="
    echo "Management Commands:"
    echo "  # View logs"
    echo "  docker compose logs -f"
    echo "  # Stop service"
    echo "  docker compose down"
    echo "  # Restart service"
    echo "  docker compose restart"
    echo "=========================================="
}

# Main process
main() {
    check_root
    install_docker
    setup_configurations
    deploy_service
    show_info
}

# Run script
main "$@"