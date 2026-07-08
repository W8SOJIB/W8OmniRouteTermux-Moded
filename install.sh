#!/bin/bash
set -e

echo "=== W8OmniRouteTermux-Moded Quick Installer ==="

# 1. Update pkg and install requirements
echo "Installing Node.js and Git..."
pkg update -y
pkg install -y nodejs git

# 2. Clone the repository
INSTALL_DIR="$HOME/W8OmniRouteTermux-Moded"
if [ -d "$INSTALL_DIR" ]; then
  echo "Installation directory $INSTALL_DIR already exists."
  echo "Updating the repository..."
  cd "$INSTALL_DIR"
  git pull
else
  echo "Cloning the modded OmniRoute repository..."
  git clone https://github.com/W8SOJIB/W8OmniRouteTermux-Moded.git "$INSTALL_DIR"
  cd "$INSTALL_DIR"
fi

# 3. Install dependencies
echo "Installing dependencies..."
npm install

# 4. Build next standalone app
echo "Building OmniRoute..."
npm run build

# 5. Install globally
echo "Installing globally..."
npm install -g .

echo "============================================="
echo "🎉 W8OmniRouteTermux-Moded installed successfully!"
echo "To start the server, run:"
echo "  omniroute serve"
echo "============================================="
