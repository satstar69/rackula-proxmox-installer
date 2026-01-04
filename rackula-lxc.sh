#!/usr/bin/env bash

# Rackula LXC Installation Script
# License: MIT
# Supports both interactive and non-interactive modes

function header_info() {
  clear
  cat <<"EOF"
    ____             __          __     
   / __ \____ ______/ /____  __/ /___ _
  / /_/ / __ `/ ___/ //_/ / / / / __ `/
 / _, _/ /_/ / /__/ ,< / /_/ / / /_/ / 
/_/ |_|\__,_/\___/_/|_|\__,_/_/\__,_/  
                                        
     Rack Layout Visualizer for Homelabbers
EOF
}

set -eEuo pipefail

# Safety checks
if ! command -v pct &> /dev/null; then
    echo "ERROR: This script must be run on a Proxmox VE host!"
    exit 1
fi

if systemd-detect-virt -c &> /dev/null; then
    echo "ERROR: This script cannot be run inside a container!"
    exit 1
fi

YW="\033[33m"
BL="\033[36m"
RD="\033[01;31m"
BGN="\033[4;92m"
GN="\033[1;92m"
DGN="\033[32m"
CL="\033[m"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
HOLD="-"

# Functions
msg_info() {
  local msg="$1"
  echo -ne " ${HOLD} ${YW}${msg}..."
}

msg_ok() {
  local msg="$1"
  echo -e "${HOLD} ${CM} ${GN}${msg}${CL}"
}

msg_error() {
  local msg="$1"
  echo -e "${HOLD} ${CROSS} ${RD}${msg}${CL}"
}

# Get next available CT ID
get_next_ctid() {
  NEXT_ID=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | jq -r '.[].vmid' 2>/dev/null | sort -n | tail -1)
  if [ -z "$NEXT_ID" ]; then
    echo "100"
  else
    echo $((NEXT_ID + 1))
  fi
}

# Check if CT exists
check_ctid_exists() {
  if pct status "$1" &>/dev/null; then
    return 0
  else
    return 1
  fi
}

# Get storage list
get_storage_list() {
  pvesm status -content rootdir | awk 'NR>1 {print $1}'
}

# Parse command line arguments or environment variables
INTERACTIVE=true

# Check for non-interactive mode
if [ "${AUTO:-}" = "yes" ] || [ "${NONINTERACTIVE:-}" = "yes" ]; then
  INTERACTIVE=false
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --auto|--yes|-y)
      INTERACTIVE=false
      shift
      ;;
    --ctid)
      CTID="$2"
      shift 2
      ;;
    --hostname)
      HOSTNAME="$2"
      shift 2
      ;;
    --password)
      PASSWORD="$2"
      shift 2
      ;;
    --storage)
      STORAGE="$2"
      shift 2
      ;;
    --disk)
      DISK_SIZE="$2"
      shift 2
      ;;
    --cores)
      CORES="$2"
      shift 2
      ;;
    --memory)
      MEMORY="$2"
      shift 2
      ;;
    --swap)
      SWAP="$2"
      shift 2
      ;;
    --bridge)
      BRIDGE="$2"
      shift 2
      ;;
    --ip)
      STATIC_IP="$2"
      shift 2
      ;;
    --gateway)
      GATEWAY="$2"
      shift 2
      ;;
    --port)
      HTTP_PORT="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --auto, -y           Non-interactive mode (use defaults)"
      echo "  --ctid ID            Container ID (default: auto)"
      echo "  --hostname NAME      Hostname (default: rackula)"
      echo "  --password PASS      Root password (default: rackula)"
      echo "  --storage NAME       Storage (default: first available)"
      echo "  --disk SIZE          Disk size in GB (default: 10)"
      echo "  --cores N            CPU cores (default: 2)"
      echo "  --memory MB          RAM in MB (default: 2048)"
      echo "  --swap MB            Swap in MB (default: 512)"
      echo "  --bridge NAME        Network bridge (default: vmbr0)"
      echo "  --ip ADDR            Static IP (e.g., 192.168.1.100/24)"
      echo "  --gateway ADDR       Gateway for static IP"
      echo "  --port PORT          HTTP port (default: 8080)"
      echo ""
      echo "Examples:"
      echo "  # Interactive mode:"
      echo "  $0"
      echo ""
      echo "  # Non-interactive with defaults:"
      echo "  $0 --auto"
      echo ""
      echo "  # Custom configuration:"
      echo "  $0 --auto --hostname myrackula --memory 4096 --port 8090"
      echo ""
      echo "  # One-liner from URL:"
      echo "  bash <(wget -qO- URL) --auto"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Interactive mode
if [ "$INTERACTIVE" = true ]; then
  header_info
  echo ""
  
  if ! whiptail --backtitle "Proxmox VE Helper Scripts" --title "Rackula LXC Installer" --yesno "This will install Rackula in a new LXC container.\n\nProceed?" 10 58; then
    echo -e "${RD}Installation cancelled${CL}"
    exit 0
  fi
  
  # Get Container ID
  SUGGESTED_CTID=$(get_next_ctid)
  CTID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Enter Container ID" 8 58 "$SUGGESTED_CTID" --title "Container ID" 3>&1 1>&2 2>&3)
  
  exitstatus=$?
  if [ $exitstatus != 0 ]; then
    echo -e "${RD}Installation cancelled${CL}"
    exit 1
  fi
  
  if check_ctid_exists "$CTID"; then
    whiptail --backtitle "Proxmox VE Helper Scripts" --title "Error" --msgbox "Container $CTID already exists!" 8 50
    exit 1
  fi
  
  # Get Hostname
  HOSTNAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Enter hostname" 8 58 "rackula" --title "Hostname" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then exit 1; fi
  
  # Get Password
  PASSWORD=$(whiptail --backtitle "Proxmox VE Helper Scripts" --passwordbox "Enter root password" 8 58 --title "Password" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then exit 1; fi
  
  PASSWORD_CONFIRM=$(whiptail --backtitle "Proxmox VE Helper Scripts" --passwordbox "Confirm root password" 8 58 --title "Confirm Password" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then exit 1; fi
  
  if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    whiptail --backtitle "Proxmox VE Helper Scripts" --title "Error" --msgbox "Passwords don't match!" 8 50
    exit 1
  fi
  
  # Get Storage
  STORAGE_LIST=()
  while read -r line; do
    STORAGE_LIST+=("$line" "")
  done < <(get_storage_list)
  
  if [ ${#STORAGE_LIST[@]} -eq 0 ]; then
    whiptail --backtitle "Proxmox VE Helper Scripts" --title "Error" --msgbox "No suitable storage found for containers!" 8 60
    exit 1
  fi
  
  STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage" --menu "\nSelect storage:" 16 58 6 "${STORAGE_LIST[@]}" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then exit 1; fi
  
  # Get Disk Size
  DISK_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Enter disk size (GB)" 8 58 "10" --title "Disk Size" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then exit 1; fi
  
  # Get CPU Cores
  CORES=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Enter number of CPU cores" 8 58 "2" --title "CPU Cores" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then exit 1; fi
  
  # Get Memory
  MEMORY=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Enter RAM (MB)" 8 58 "2048" --title "Memory" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then exit 1; fi
  
  # Get Swap
  SWAP=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Enter SWAP (MB)" 8 58 "512" --title "Swap" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then exit 1; fi
  
  # Get Bridge
  BRIDGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Enter network bridge" 8 58 "vmbr0" --title "Network Bridge" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then exit 1; fi
  
  # IP Configuration
  IP_TYPE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Network Configuration" --menu "\nSelect IP configuration:" 12 58 2 \
    "1" "DHCP" \
    "2" "Static IP" 3>&1 1>&2 2>&3)
  
  if [ $? -ne 0 ]; then exit 1; fi
  
  if [ "$IP_TYPE" = "2" ]; then
    STATIC_IP=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Enter static IP (e.g., 192.168.1.100/24)" 8 58 --title "Static IP" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 1; fi
    
    GATEWAY=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Enter gateway" 8 58 --title "Gateway" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 1; fi
    
    NET_CONFIG="name=eth0,bridge=$BRIDGE,ip=$STATIC_IP,gw=$GATEWAY"
  else
    NET_CONFIG="name=eth0,bridge=$BRIDGE,ip=dhcp"
  fi
  
  # Get HTTP Port
  HTTP_PORT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Enter HTTP port for Rackula" 8 58 "8080" --title "HTTP Port" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then exit 1; fi
  
  ONBOOT_FLAG=1
  
  # Confirmation
  SUMMARY="Container ID: $CTID\nHostname: $HOSTNAME\nStorage: $STORAGE\nDisk: ${DISK_SIZE}GB\nCPU: $CORES cores\nRAM: ${MEMORY}MB\nSwap: ${SWAP}MB\nNetwork: $NET_CONFIG\nHTTP Port: $HTTP_PORT"
  
  if ! whiptail --backtitle "Proxmox VE Helper Scripts" --title "Confirm Installation" --yesno "$SUMMARY\n\nProceed with installation?" 18 70; then
    echo -e "${RD}Installation cancelled${CL}"
    exit 1
  fi

else
  # Non-interactive mode - use defaults or provided values
  header_info
  echo -e "\n${GN}Running in non-interactive mode...${CL}\n"
  
  CTID="${CTID:-$(get_next_ctid)}"
  HOSTNAME="${HOSTNAME:-rackula}"
  PASSWORD="${PASSWORD:-rackula}"
  DISK_SIZE="${DISK_SIZE:-10}"
  CORES="${CORES:-2}"
  MEMORY="${MEMORY:-2048}"
  SWAP="${SWAP:-512}"
  BRIDGE="${BRIDGE:-vmbr0}"
  HTTP_PORT="${HTTP_PORT:-8080}"
  ONBOOT_FLAG=1
  
  # Get first available storage if not specified
  if [ -z "${STORAGE:-}" ]; then
    STORAGE=$(get_storage_list | head -1)
    if [ -z "$STORAGE" ]; then
      msg_error "No suitable storage found"
      exit 1
    fi
  fi
  
  # Check if CTID already exists
  if check_ctid_exists "$CTID"; then
    msg_error "Container $CTID already exists"
    exit 1
  fi
  
  # Network configuration
  if [ -n "${STATIC_IP:-}" ] && [ -n "${GATEWAY:-}" ]; then
    NET_CONFIG="name=eth0,bridge=$BRIDGE,ip=$STATIC_IP,gw=$GATEWAY"
  else
    NET_CONFIG="name=eth0,bridge=$BRIDGE,ip=dhcp"
  fi
  
  echo -e "${BL}Container ID:${CL} $CTID"
  echo -e "${BL}Hostname:${CL} $HOSTNAME"
  echo -e "${BL}Storage:${CL} $STORAGE"
  echo -e "${BL}Resources:${CL} ${CORES} cores, ${MEMORY}MB RAM, ${DISK_SIZE}GB disk"
  echo -e "${BL}Network:${CL} $NET_CONFIG"
  echo -e "${BL}HTTP Port:${CL} $HTTP_PORT"
  echo ""
fi

# Get Template
TEMPLATE_UBUNTU=$(pveam list local 2>/dev/null | grep -E "ubuntu-(25\.04|24\.04)" | head -1 | awk '{print $1}')

if [ -z "$TEMPLATE_UBUNTU" ]; then
  msg_info "Downloading Ubuntu template"
  
  UBUNTU_TEMPLATE=$(pveam available 2>/dev/null | grep ubuntu-25.04 | grep standard | head -1 | awk '{print $2}')
  
  if [ -z "$UBUNTU_TEMPLATE" ]; then
    UBUNTU_TEMPLATE=$(pveam available 2>/dev/null | grep ubuntu-24.04 | grep standard | head -1 | awk '{print $2}')
  fi
  
  if [ -z "$UBUNTU_TEMPLATE" ]; then
    msg_error "Could not find Ubuntu template"
    exit 1
  fi
  
  pveam download local "$UBUNTU_TEMPLATE" >/dev/null 2>&1
  TEMPLATE="local:vztmpl/$UBUNTU_TEMPLATE"
  msg_ok "Template downloaded"
else
  TEMPLATE="$TEMPLATE_UBUNTU"
fi

# Create container
if [ "$INTERACTIVE" = false ]; then
  header_info
fi

msg_info "Creating LXC container"

pct create "$CTID" "$TEMPLATE" \
  --hostname "$HOSTNAME" \
  --password "$PASSWORD" \
  --cores "$CORES" \
  --memory "$MEMORY" \
  --swap "$SWAP" \
  --rootfs "$STORAGE:$DISK_SIZE" \
  --net0 "$NET_CONFIG" \
  --features nesting=1 \
  --unprivileged 1 \
  --onboot "$ONBOOT_FLAG" >/dev/null 2>&1

msg_ok "Container created"

msg_info "Starting container"
pct start "$CTID"
sleep 5
msg_ok "Container started"

# Create installation script
cat >/tmp/rackula-install.sh <<INSTALL_EOF
#!/bin/bash
set -e

YW="\033[33m"
BL="\033[36m"
GN="\033[1;92m"
CL="\033[m"
CM="\${GN}✓\${CL}"

echo -e "\n\${GN}Installing Rackula...\${CL}\n"

# Update system
echo -ne " - \${YW}Updating system..."
export DEBIAN_FRONTEND=noninteractive
apt-get update >/dev/null 2>&1
apt-get upgrade -y >/dev/null 2>&1
echo -e " \${CM}"

# Install dependencies
echo -ne " - \${YW}Installing dependencies..."
apt-get install -y curl wget git ca-certificates gnupg nginx figlet >/dev/null 2>&1
echo -e " \${CM}"

# Install Node.js
echo -ne " - \${YW}Installing Node.js 20.x..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
apt-get install -y nodejs >/dev/null 2>&1
echo -e " \${CM}"

# Clone repository
echo -ne " - \${YW}Cloning Rackula repository..."
cd /opt
git clone https://github.com/rackulalives/rackula.git >/dev/null 2>&1
cd rackula
echo -e " \${CM}"

# Install npm dependencies
echo -ne " - \${YW}Installing npm packages..."
npm install >/dev/null 2>&1
echo -e " \${CM}"

# Build
echo -ne " - \${YW}Building Rackula..."
npm run build >/dev/null 2>&1
echo -e " \${CM}"

# Configure Nginx
echo -ne " - \${YW}Configuring Nginx..."
cat > /etc/nginx/sites-available/rackula <<'NGINX_EOF'
server {
    listen $HTTP_PORT;
    server_name _;
    
    root /opt/rackula/dist;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        access_log off;
    }
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
}
NGINX_EOF

ln -sf /etc/nginx/sites-available/rackula /etc/nginx/sites-enabled/rackula
rm -f /etc/nginx/sites-enabled/default
nginx -t >/dev/null 2>&1
systemctl enable nginx >/dev/null 2>&1
systemctl restart nginx
echo -e " \${CM}"

# Configure MOTD
echo -ne " - \${YW}Configuring MOTD..."
chmod -x /etc/update-motd.d/* 2>/dev/null || true

cat > /etc/update-motd.d/00-rackula-header <<'MOTD_EOF'
#!/bin/bash

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOSTNAME=\$(hostname)
IP_ADDRESS=\$(hostname -I | awk '{print \$1}')
HTTP_PORT=$HTTP_PORT

clear
echo ""
echo -e "\${GREEN}"
figlet -f standard "Rackula"
echo -e "\${NC}"
echo -e "\${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\${NC}"
echo -e "\${GREEN}  Container:\${NC} \${HOSTNAME}"
echo -e "\${GREEN}  IP Address:\${NC} \${IP_ADDRESS}"
echo -e "\${GREEN}  Web Interface:\${NC} \${YELLOW}http://\${IP_ADDRESS}:\${HTTP_PORT}\${NC}"
echo -e "\${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\${NC}"
echo ""
echo -e "\${CYAN}📦 Drag & Drop Rack Visualizer for Homelabbers\${NC}"
echo ""
echo -e "  • Real device images from NetBox library"
echo -e "  • Export to PNG, PDF, SVG"
echo -e "  • QR code sharing"
echo ""
echo -e "\${YELLOW}Quick Commands:\${NC}"
echo -e "  \${GREEN}update\${NC}             Update Rackula to latest version"
echo -e "  \${GREEN}rackula-logs\${NC}       View access logs"
echo -e "  \${GREEN}rackula-status\${NC}     Check Nginx status"
echo -e "  \${GREEN}rackula-restart\${NC}    Restart Nginx"
echo ""
MOTD_EOF

chmod +x /etc/update-motd.d/00-rackula-header

cat > /etc/profile.d/rackula-motd.sh <<'PROFILE_EOF'
if [ -f /etc/update-motd.d/00-rackula-header ]; then
    /etc/update-motd.d/00-rackula-header
fi
PROFILE_EOF

chmod +x /etc/profile.d/rackula-motd.sh
echo -e " \${CM}"

# Create update command
echo -ne " - \${YW}Creating update command..."
cat > /usr/local/bin/rackula-update <<'UPDATE_CMD'
#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "\${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\${NC}"
echo -e "\${GREEN}  Rackula Update\${NC}"
echo -e "\${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\${NC}"
echo ""

if [ ! -d "/opt/rackula" ]; then
    echo -e "\${RED}Error: Rackula not found in /opt/rackula\${NC}"
    exit 1
fi

cd /opt/rackula

# Get current commit
CURRENT_COMMIT=\$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
echo -e "\${YELLOW}Current version:\${NC} \${CURRENT_COMMIT}"
echo ""

# Update repository
echo -ne "Updating repository... "
git fetch origin >/dev/null 2>&1
git pull origin main >/dev/null 2>&1
NEW_COMMIT=\$(git rev-parse --short HEAD)
echo -e "\${GREEN}✓\${NC}"

if [ "\${CURRENT_COMMIT}" != "\${NEW_COMMIT}" ]; then
    echo -e "\${GREEN}Updated:\${NC} \${CURRENT_COMMIT} → \${NEW_COMMIT}"
else
    echo -e "\${GREEN}Already up to date\${NC}"
fi

# Install dependencies
echo -ne "Installing dependencies... "
npm install >/dev/null 2>&1
echo -e "\${GREEN}✓\${NC}"

# Build
echo -ne "Building Rackula... "
npm run build >/dev/null 2>&1
echo -e "\${GREEN}✓\${NC}"

# Restart Nginx
echo -ne "Restarting Nginx... "
systemctl restart nginx
echo -e "\${GREEN}✓\${NC}"

echo ""
echo -e "\${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\${NC}"
echo -e "\${GREEN}Update complete!\${NC}"
echo -e "\${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\${NC}"
echo ""

IP_ADDRESS=\$(hostname -I | awk '{print \$1}')
HTTP_PORT=$HTTP_PORT
echo -e "Access Rackula at: \${YELLOW}http://\${IP_ADDRESS}:\${HTTP_PORT}\${NC}"
echo ""
UPDATE_CMD

chmod +x /usr/local/bin/rackula-update

# Create convenient aliases
cat >> /root/.bashrc <<'ALIAS_EOF'

# Rackula shortcuts
alias update='rackula-update'
alias rackula-logs='tail -f /var/log/nginx/access.log'
alias rackula-status='systemctl status nginx'
alias rackula-restart='systemctl restart nginx'
ALIAS_EOF

echo -e " \${CM}"

CONTAINER_IP=\$(hostname -I | awk '{print \$1}')
echo -e "\n\${GN}Installation complete!\${CL}"
echo -e "\${BL}Access at: \${YW}http://\${CONTAINER_IP}:$HTTP_PORT\${CL}\n"
INSTALL_EOF

# Execute installation
msg_info "Installing Rackula (this may take several minutes)"
pct push "$CTID" /tmp/rackula-install.sh /root/install.sh
pct exec "$CTID" -- bash -c "export HTTP_PORT='$HTTP_PORT' && bash /root/install.sh"
rm -f /tmp/rackula-install.sh
msg_ok "Installation complete"

# Get container IP
CONTAINER_IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')

# Final message
header_info
echo -e "${GN}Rackula successfully installed!${CL}\n"
echo -e "${BL}Container ID:${CL} $CTID"
echo -e "${BL}Hostname:${CL} $HOSTNAME"
echo -e "${BL}IP Address:${CL} $CONTAINER_IP"
echo -e "${BL}Root Password:${CL} $PASSWORD"
echo -e "\n${YW}Access Rackula at:${CL} ${BGN}http://$CONTAINER_IP:$HTTP_PORT${CL}\n"
echo -e "${GN}MOTD banner configured - connection info shown on login${CL}\n"
echo -e "${DGN}Quick Commands (inside container):${CL}"
echo -e "  ${BL}update${CL}             Update Rackula to latest version"
echo -e "  ${BL}rackula-logs${CL}       View access logs"
echo -e "  ${BL}rackula-status${CL}     Check Nginx status"
echo -e "  ${BL}rackula-restart${CL}    Restart Nginx"
echo -e "\n${DGN}Enter container:${CL} ${BL}pct enter $CTID${CL}\n"
