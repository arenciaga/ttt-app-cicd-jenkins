#!/bin/bash

set -e

echo ">>> Updating and upgrading..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

echo ">>> Installing nginx..."
sudo apt-get install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx

echo ">>> Installing Node.js v20..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

echo ">>> Installing pm2..."
sudo npm install -g pm2

REPO_URL="https://github.com/arenciaga/nodejs-app"
REPO_DIR="/home/ubuntu/nodejs-app"

if [ -d "$REPO_DIR/.git" ]; then
  echo ">>> Repo exists, pulling latest..."
  git -C "$REPO_DIR" pull
else
  echo ">>> Cloning repo..."
  git clone "$REPO_URL" "$REPO_DIR"
fi

cd "$REPO_DIR/app"
npm install

pm2 stop app 2>/dev/null || true
pm2 delete app 2>/dev/null || true

pm2 start index.js --name "app"

echo ">>> Done!"
pm2 status
