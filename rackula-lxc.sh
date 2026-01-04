#!/bin/bash
set -e

YW="\033[33m"
BL="\033[36m"
GN="\033[1;92m"
CL="\033[m"
CM="${GN}✓${CL}"

echo -e "\n${GN}Installing Rackula...${CL}\n"

# Update system
echo -ne " - ${YW}Updating system..."
export DEBIAN_FRONTEND=noninteractive
apt-get update >/dev/null 2>&1
apt-get upgrade -y >/dev/null 2>&1
echo -e " ${CM}"

# Install dependencies
echo -ne " - ${YW}Installing dependencies..."
apt-get install -y curl wget git ca-certificates gnupg nginx figlet >/dev/null 2>&1
echo -e " ${CM}"

# Install Node.js
echo -ne " - ${YW}Installing Node.js 20.x..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
apt-get install -y nodejs >/dev/null 2>&1
echo -e " ${CM}"

# Clone repository
echo -ne " - ${YW}Cloning Rackula repository..."
cd /opt
git clone https://github.com/rackulalives/rackula.git >/dev/null 2>&1
cd rackula
echo -e " ${CM}"

# Install npm dependencies
echo -ne " - ${YW}Installing npm packages..."
npm install >/dev/null 2>&1
echo -e " ${CM}"

# Build
echo -ne " - ${YW}Building Rackula..."
npm run build >/dev/null 2>&1
echo -e " ${CM}"

# Configure Nginx
echo -ne " - ${YW}Configuring Nginx..."
cat > /etc/nginx/sites-available/rackula <<'NGINX_EOF'
server {
    listen $HTTP_PORT;
    server_name _;
    
    root /opt/rackula/dist;
    index index.html;
    
    location / {
        try_files $uri $uri/ /index.html;
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
echo -e " ${CM}"

# Configure MOTD
echo -ne " - ${YW}Configuring MOTD..."
chmod -x /etc/update-motd.d/* 2>/dev/null || true

cat > /etc/update-motd.d/00-rackula-header <<'MOTD_EOF'
#!/bin/bash

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOSTNAME=$(hostname)
IP_ADDRESS=$(hostname -I | awk '{print $1}')
HTTP_PORT=$HTTP_PORT

clear
echo ""
echo -e "${GREEN}"
figlet -f standard "Rackula"
echo -e "${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Container:${NC} ${HOSTNAME}"
echo -e "${GREEN}  IP Address:${NC} ${IP_ADDRESS}"
echo -e "${GREEN}  Web Interface:${NC} ${YELLOW}http://${IP_ADDRESS}:${HTTP_PORT}${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}📦 Drag & Drop Rack Visualizer for Homelabbers${NC}"
echo ""
echo -e "  • Real device images from NetBox library"
echo -e "  • Export to PNG, PDF, SVG"
echo -e "  • QR code sharing"
echo ""
echo -e "${YELLOW}Quick Commands:${NC}"
echo -e "  ${GREEN}update${NC}             Update Rackula to latest version"
echo -e "  ${GREEN}rackula-logs${NC}       View access logs"
echo -e "  ${GREEN}rackula-status${NC}     Check Nginx status"
echo -e "  ${GREEN}rackula-restart${NC}    Restart Nginx"
echo ""
MOTD_EOF

chmod +x /etc/update-motd.d/00-rackula-header

cat > /etc/profile.d/rackula-motd.sh <<'PROFILE_EOF'
if [ -f /etc/update-motd.d/00-rackula-header ]; then
    /etc/update-motd.d/00-rackula-header
fi
PROFILE_EOF

chmod +x /etc/profile.d/rackula-motd.sh
echo -e " ${CM}"

# Create update command
echo -ne " - ${YW}Creating update command..."
cat > /usr/local/bin/rackula-update <<'UPDATE_CMD'
#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Rackula Update${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ ! -d "/opt/rackula" ]; then
    echo -e "${RED}Error: Rackula not found in /opt/rackula${NC}"
    exit 1
fi

cd /opt/rackula

# Get current commit
CURRENT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
echo -e "${YELLOW}Current version:${NC} ${CURRENT_COMMIT}"
echo ""

# Update repository
echo -ne "Updating repository... "
git fetch origin >/dev/null 2>&1
git pull origin main >/dev/null 2>&1
NEW_COMMIT=$(git rev-parse --short HEAD)
echo -e "${GREEN}✓${NC}"

if [ "${CURRENT_COMMIT}" != "${NEW_COMMIT}" ]; then
    echo -e "${GREEN}Updated:${NC} ${CURRENT_COMMIT} → ${NEW_COMMIT}"
else
    echo -e "${GREEN}Already up to date${NC}"
fi

# Install dependencies
echo -ne "Installing dependencies... "
npm install >/dev/null 2>&1
echo -e "${GREEN}✓${NC}"

# Build
echo -ne "Building Rackula... "
npm run build >/dev/null 2>&1
echo -e "${GREEN}✓${NC}"

# Restart Nginx
echo -ne "Restarting Nginx... "
systemctl restart nginx
echo -e "${GREEN}✓${NC}"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Update complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

IP_ADDRESS=$(hostname -I | awk '{print $1}')
HTTP_PORT=$HTTP_PORT
echo -e "Access Rackula at: ${YELLOW}http://${IP_ADDRESS}:${HTTP_PORT}${NC}"
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

echo -e " ${CM}"

CONTAINER_IP=$(hostname -I | awk '{print $1}')
echo -e "\n${GN}Installation complete!${CL}"
echo -e "${BL}Access at: ${YW}http://${CONTAINER_IP}:$HTTP_PORT${CL}\n"
