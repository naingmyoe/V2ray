#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${RED}=========================================${NC}"
echo -e "${RED}   OUTLINE PANEL UNINSTALLER             ${NC}"
echo -e "${RED}=========================================${NC}"

echo "Stopping services..."

# 1. Stop & Delete PM2 Processes
pm2 delete outline-secure 2>/dev/null
pm2 delete outline-guard 2>/dev/null
pm2 delete outline-web 2>/dev/null
pm2 delete outline-bot 2>/dev/null

# Save PM2 changes
pm2 save

echo "Removing files..."

# 2. Remove Directories
rm -rf /opt/outline-secure
rm -rf /opt/outline-manager
rm -rf /opt/outline-vps-db

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   SUCCESSFULLY REMOVED!                 ${NC}"
echo -e "${GREEN}=========================================${NC}"
