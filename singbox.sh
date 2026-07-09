#!/bin/bash

# Sing-box Server Management Panel
set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
    else
        log_error "Docker installation failed."
        exit 1
    fi
}

# Install qrencode if missing
install_qrencode() {
    if command -v qrencode &> /dev/null; then
        return
    fi

    log_info "Installing qrencode for terminal QR code generation..."
    if command -v apt-get &> /dev/null; then
        apt-get update -y && apt-get install -y qrencode
    elif command -v yum &> /dev/null; then
        yum install -y qrencode
    else
        log_warn "Unsupported package manager. Please install 'qrencode' manually to use QR features."
    fi
}

# Setup folders and configurations (Incremental User logic)
setup_configurations() {
    log_info "Setting up configuration directory..."
    mkdir -p config
    chmod 755 config

    # Ensure users.txt exists
    if [ ! -f "config/users.txt" ]; then
        log_info "users.txt not found. Creating default config/users.txt with 'admin'..."
        cat <<EOF > config/users.txt
admin
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

    # Generate self-signed TLS certificates for Trojan if they don't exist
    if [ ! -f "config/cert.pem" ] || [ ! -f "config/cert.key" ]; then
        log_info "Generating self-signed TLS certificates for Trojan..."
        openssl req -x509 -nodes -newkey rsa:2048 -keyout config/cert.key -out config/cert.pem -subj "/CN=${CONNECTION_ADDRESS:-proxy.local}" -days 3650 2>/dev/null
        chmod 644 config/cert.pem config/cert.key
    fi

    # Detect public IP
    log_info "Detecting server public IP..."
    SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org || curl -s --max-time 5 https://ifconfig.me || echo "")
    
    # Prompt for domain (only during install or if connection_address is missing/changing)
    CONNECTION_ADDRESS=""
    if [ -f "config/client_links.txt" ]; then
        # Try to extract the address used previously
        CONNECTION_ADDRESS=$(grep -o "@[^:]*" config/client_links.txt | head -n 1 | tr -d '@' || echo "")
    fi

    if [ -z "$CONNECTION_ADDRESS" ]; then
        echo -e "${YELLOW}------------------------------------------${NC}"
        if [ -n "$SERVER_IP" ]; then
            read -p "Please enter the domain name bound to this Sing-box service (Press Enter to use Public IP: $SERVER_IP): " USER_DOMAIN
        else
            read -p "Failed to detect public IP. Please enter your domain name or public IP: " USER_DOMAIN
        fi
        echo -e "${YELLOW}------------------------------------------${NC}"

        if [ -n "$USER_DOMAIN" ]; then
            CONNECTION_ADDRESS=$(echo "$USER_DOMAIN" | tr -d '[:space:]')
        else
            CONNECTION_ADDRESS="$SERVER_IP"
            if [ -z "$CONNECTION_ADDRESS" ]; then
                log_error "No address provided and failed to automatically detect public IP."
                exit 1
            fi
        fi
    fi

    # Resolve domain to IP for client config (eliminates DNS bootstrap dependency)
    if echo "$CONNECTION_ADDRESS" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        SERVER_CONNECT_IP="$CONNECTION_ADDRESS"
    else
        SERVER_CONNECT_IP=$(dig +short A "$CONNECTION_ADDRESS" 2>/dev/null | grep -E '^[0-9]+' | head -1)
        if [ -z "$SERVER_CONNECT_IP" ]; then
            SERVER_CONNECT_IP=$(nslookup "$CONNECTION_ADDRESS" 2>/dev/null | awk '/Address:/ {print $2}' | grep -v '#' | head -1)
        fi
        if [ -z "$SERVER_CONNECT_IP" ]; then
            SERVER_CONNECT_IP=$(python3 -c "import socket; print(socket.gethostbyname('$CONNECTION_ADDRESS'))" 2>/dev/null || echo "")
        fi
        if [ -z "$SERVER_CONNECT_IP" ]; then
            log_warn "Could not resolve $CONNECTION_ADDRESS to IP, using domain directly."
            SERVER_CONNECT_IP="$CONNECTION_ADDRESS"
        else
            log_info "Resolved $CONNECTION_ADDRESS -> $SERVER_CONNECT_IP (used in client config)"
        fi
    fi



    # Clean up ALL generated config files atomically to prevent stale files from lingering.
    # Using rm -rf + mkdir is safer than glob (glob silently fails when dir is empty or missing).
    rm -f config/*_client.json          # per-user client configs
    mkdir -p config/subs
    find config/subs -name "*.json" -delete  # clear subs without removing the dir (preserves nginx volume mount)

    # Process each user
    USERS_JSON=""
    NEW_CLIENT_LINKS=""
    first=true

    for username in "${USERS[@]}"; do
        UUID=""
        # Try to find existing UUID to keep client connection intact
        if [ -f "config/config.json" ]; then
            UUID=$(python3 -c "import json; config = json.load(open('config/config.json')); users = config['inbounds'][0]['users']; print(next((u.get('password', u.get('uuid', '')) for u in users if u['name'] == '$username'), ''))" 2>/dev/null \
                   || python -c "import json; config = json.load(open('config/config.json')); users = config['inbounds'][0]['users']; print(next((u.get('password', u.get('uuid', '')) for u in users if u['name'] == '$username'), ''))" 2>/dev/null \
                   || echo "")
            
            # Fallback to grep
            if [ -z "$UUID" ] && [ -f "config/client_links.txt" ]; then
                EXISTING_LINE=$(grep "^${username}: trojan://" config/client_links.txt || grep "^${username}: vless://" config/client_links.txt || echo "")
                if [ -n "$EXISTING_LINE" ]; then
                    UUID=$(echo "$EXISTING_LINE" | cut -d '/' -f 3 | cut -d '@' -f 1)
                fi
            fi
        fi

        if [ -n "$UUID" ]; then
            UUID=$(echo "$UUID" | tr -d '\r\n')
        else
            UUID=$(docker run --rm ghcr.io/sagernet/sing-box:latest generate uuid | tr -d '\r\n')
            log_info "Generated a new password/UUID for user '$username'."
        fi

        # Build users array JSON
        if [ "$first" = true ]; then
            first=false
        else
            USERS_JSON="$USERS_JSON,"
        fi
        USERS_JSON="$USERS_JSON{\"name\": \"$username\", \"password\": \"$UUID\"}"

        # Generate client link
        LINK="trojan://$UUID@$CONNECTION_ADDRESS:443?sni=$CONNECTION_ADDRESS&allowInsecure=1#singbox-$username"
        NEW_CLIENT_LINKS="$NEW_CLIENT_LINKS${username}: ${LINK}"$'\n'

        # Generate client JSON config
        cat <<EOF > config/${username}_client.json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "dns-remote",
        "address": "https://8.8.8.8/dns-query",
        "detour": "proxy"
      },
      {
        "tag": "dns-local",
        "address": "local"
      }
    ]
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "tun0",
      "address": [
        "172.19.0.1/30"
      ],
      "auto_route": true,
      "strict_route": true,
      "stack": "system"
    }
  ],
  "outbounds": [
    {
      "type": "trojan",
      "tag": "proxy",
      "server": "$SERVER_CONNECT_IP",
      "server_port": 443,
      "password": "$UUID",
      "tls": {
        "enabled": true,
        "server_name": "$CONNECTION_ADDRESS",
        "insecure": true,
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        }
      }
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "default_domain_resolver": {
      "server": "dns-local"
    },
    "rules": [
      {
        "inbound": [
          "tun-in"
        ],
        "action": "sniff"
      },
      {
        "protocol": "dns",
        "action": "hijack-dns"
      },
      {
        "ip_is_private": true,
        "outbound": "direct"
      }
    ]
  }
}
EOF
        SUB_HASH=$(echo -n "$UUID" | openssl dgst -md5 | awk '{print $NF}')
        cp config/${username}_client.json config/subs/${SUB_HASH}.json
    done

    # Write config.json
    cat <<EOF > config/config.json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "dns-local",
        "type": "udp",
        "server": "8.8.8.8"
      }
    ]
  },
  "route": {
    "default_domain_resolver": {
      "server": "dns-local"
    }
  },
  "inbounds": [
    {
      "type": "trojan",
      "tag": "trojan-in",
      "listen": "::",
      "listen_port": 443,
      "users": [
        $USERS_JSON
      ],
      "tls": {
        "enabled": true,
        "key_path": "/etc/sing-box/cert.key",
        "certificate_path": "/etc/sing-box/cert.pem"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

    # Save links
    echo -n "$NEW_CLIENT_LINKS" > config/client_links.txt
}

# --- Action Functions ---

action_install() {
    log_info "Starting environment setup..."
    check_root
    install_docker
    setup_configurations
    
    log_info "Deploying Sing-box container..."
    docker compose up -d --force-recreate
    
    # Wait for service initialization
    sleep 3
    if docker compose ps | grep -q "Up"; then
        log_info "Sing-box has been deployed successfully."
        action_show_links
    else
        log_error "Sing-box container failed to start. Logs:"
        docker compose logs --tail=20
    fi
}

action_start() {
    log_info "Starting Sing-box service..."
    docker compose up -d
    sleep 2
    if docker compose ps | grep -q "Up"; then
        log_info "Sing-box service started."
    else
        log_error "Failed to start service."
    fi
}

action_stop() {
    log_info "Stopping Sing-box service..."
    docker compose down
    log_info "Sing-box service stopped."
}

action_restart() {
    log_info "Restarting Sing-box service..."
    docker compose restart sing-box
    log_info "Sing-box service restarted."
}

action_uninstall() {
    echo -e "${RED}==========================================${NC}"
    echo -e "${RED}               WARNING!                   ${NC}"
    echo -e "${RED}==========================================${NC}"
    echo -e "This will stop the containers, delete the Sing-box Docker image, and delete all persistent config data."
    read -p "Are you absolutely sure you want to uninstall Sing-box? [y/N]: " confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
        log_info "Uninstalling service..."
        docker compose down --rmi all 2>/dev/null || docker compose down
        rm -rf config
        log_info "Sing-box service has been completely uninstalled."
    else
        log_info "Uninstallation cancelled."
    fi
}

action_update() {
    log_info "Checking and pulling the latest official Sing-box image..."
    docker compose pull
    log_info "Applying changes..."
    docker compose up -d
    docker compose restart sing-box
    
    # Show updated version
    log_info "Current running Sing-box version:"
    docker compose exec -T sing-box sing-box version | head -n 1 || true
}

action_show_links() {
    if [ ! -f "config/client_links.txt" ]; then
        log_error "No configurations found. Please run installation first."
        return
    fi

    install_qrencode

    local has_qrencode=false
    if command -v qrencode &> /dev/null; then
        has_qrencode=true
    fi

    echo -e "${YELLOW}------------------------------------------${NC}"
    echo -e "${YELLOW}       Client VLESS Links & QR Codes      ${NC}"
    echo -e "${YELLOW}------------------------------------------${NC}"
    
    local i=1
    while IFS= read -r line || [[ -n "$line" ]]; do
        local user_name=$(echo "$line" | cut -d ':' -f 1)
        local link_url=$(echo "$line" | cut -d ' ' -f 2-)
        echo -e "$i. ${YELLOW}[User: $user_name]${NC}"
        echo -e "VLESS Share Link: ${GREEN}$link_url${NC}"
        if [ "$has_qrencode" = true ]; then
            echo -e "${YELLOW}[QR Code for VLESS Share Link]${NC}"
            qrencode -t ansiutf8 "$link_url"
        else
            log_warn "qrencode is not installed. Cannot display QR code."
        fi
        
        # Sing-box client remote profile link
        local uuid_extracted=$(echo "$link_url" | cut -d '/' -f 3 | cut -d '@' -f 1)
        local conn_addr_extracted=$(echo "$link_url" | cut -d '@' -f 2 | cut -d ':' -f 1)
        local sub_hash_extracted=$(echo -n "$uuid_extracted" | openssl dgst -md5 | awk '{print $NF}')
        local sub_url_val="http://${conn_addr_extracted}:8080/subs/${sub_hash_extracted}.json"
        local url_encoded_sub=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$sub_url_val'''))" 2>/dev/null || echo -n "$sub_url_val" | sed 's/:/%3A/g; s/\//%2F/g')
        local singbox_import_link="sing-box://import-remote-profile?url=${url_encoded_sub}#singbox-${user_name}"
        
        echo -e "Sing-box Client Import Link: ${BLUE}${singbox_import_link}${NC}"
        if [ "$has_qrencode" = true ]; then
            echo -e "${YELLOW}[QR Code for Sing-box Client Import]${NC}"
            qrencode -t ansiutf8 "$singbox_import_link"
        fi
        
        if [ -f "config/${user_name}_client.json" ]; then
            echo -e "Client JSON config saved locally: ${BLUE}config/${user_name}_client.json${NC}"
        fi
        echo ""
        i=$((i+1))
    done < config/client_links.txt
    echo -e "${YELLOW}------------------------------------------${NC}"
}

action_add_user() {
    if [ ! -f "config/users.txt" ]; then
        log_error "Configuration folder not found. Please install the service first."
        return
    fi

    read -p "Enter new username to add: " new_username
    new_username=$(echo "$new_username" | xargs 2>/dev/null || echo "$new_username" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    
    if [ -z "$new_username" ]; then
        log_error "Username cannot be empty."
        return
    fi

    if grep -q "^${new_username}$" config/users.txt; then
        log_error "User '$new_username' already exists."
        return
    fi

    echo "$new_username" >> config/users.txt
    log_info "Adding user '$new_username'..."
    setup_configurations
    
    # Reload/restart sing-box to apply changes
    docker compose up -d
    docker compose restart sing-box
    log_info "User '$new_username' added successfully."
}

action_delete_user() {
    if [ ! -f "config/users.txt" ]; then
        log_error "Configuration folder not found. Please install the service first."
        return
    fi

    # Read current users
    local i=1
    local display_users=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        local clean_line=$(echo "$line" | xargs 2>/dev/null || echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [ -n "$clean_line" ] && [[ ! "$clean_line" =~ ^# ]]; then
            display_users+=("$clean_line")
            echo "$i. $clean_line"
            i=$((i+1))
        fi
    done < config/users.txt

    if [ ${#display_users[@]} -eq 0 ]; then
        log_warn "No active users found to delete."
        return
    fi

    read -p "Enter the number of the user you want to delete [1-${#display_users[@]}]: " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#display_users[@]} ]; then
        log_error "Invalid selection."
        return
    fi

    local target_user="${display_users[$((choice-1))]}"
    read -p "Are you sure you want to delete user '$target_user'? [y/N]: " confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
        # Delete row in users.txt
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "/^${target_user}$/d" config/users.txt
        else
            sed -i "/^${target_user}$/d" config/users.txt
        fi

        log_info "Removing user '$target_user' from configuration..."
        setup_configurations
        docker compose up -d
        docker compose restart sing-box
        log_info "User '$target_user' deleted successfully."
    else
        log_info "Deletion cancelled."
    fi
}

action_logs() {
    log_info "Displaying real-time logs (Ctrl+C to exit)..."
    docker compose logs -f --tail 100 sing-box
}

# Print main menu
show_menu() {
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}     Sing-box Server Management Panel     ${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo -e " 1. Install & Deploy Service"
    echo -e " 2. Start Service"
    echo -e " 3. Stop Service"
    echo -e " 4. Restart Service"
    echo -e " 5. Uninstall Service"
    echo -e " 6. Update Sing-box Version"
    echo -e " 7. Show VLESS Links & QR Codes"
    echo -e " 8. Add User"
    echo -e " 9. Delete User"
    echo -e " 10. View Real-time Logs"
    echo -e " 0. Exit"
    echo -e "${BLUE}==========================================${NC}"
}

# Main loop
main() {
    check_root
    while true; do
        show_menu
        read -p "Please enter your choice [0-10]: " choice
        case "$choice" in
            1) action_install ;;
            2) action_start ;;
            3) action_stop ;;
            4) action_restart ;;
            5) action_uninstall ;;
            6) action_update ;;
            7) action_show_links ;;
            8) action_add_user ;;
            9) action_delete_user ;;
            10) action_logs ;;
            0)
                log_info "Exiting Management Panel. Goodbye!"
                exit 0
                ;;
            *)
                log_error "Invalid choice! Please choose a number from 0 to 10."
                echo ""
                ;;
        esac
        echo -e "\nPress Enter to return to the main menu..."
        read
        clear
    done
}

# Run program
main "$@"