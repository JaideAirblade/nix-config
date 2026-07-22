#!/usr/bin/env bash
# Deep-Live-Cam setup script for NixOS (UwU).
#
# This script sets up Deep-Live-Cam in a venv at ~/projects/deep-live-cam.
# It requires the facemask NixOS module (v4l2loopback + python311) to be
# built and activated first.
#
# Run AFTER: sudo nixos-rebuild switch --flake .#UwU
#
# Usage: bash setup-deep-live-cam.sh
set -euo pipefail

PROJECTS_DIR="$HOME/projects"
DLC_DIR="$PROJECTS_DIR/deep-live-cam"
VENV_DIR="$DLC_DIR/venv"

echo "=== Deep-Live-Cam Setup ==="
echo ""

# Check python3.11 is available (from NixOS config)
if ! command -v python3.11 &>/dev/null; then
  echo "ERROR: python3.11 not found. Did you rebuild NixOS with the facemask module?"
  echo "Run: sudo nixos-rebuild switch --flake .#UwU"
  exit 1
fi

echo "[1/7] Creating projects directory..."
mkdir -p "$PROJECTS_DIR"

echo "[2/7] Cloning Deep-Live-Cam..."
if [ -d "$DLC_DIR/.git" ]; then
  echo "  Already cloned, pulling latest..."
  cd "$DLC_DIR"
  git pull
else
  git clone https://github.com/hacksider/Deep-Live-Cam.git "$DLC_DIR"
  cd "$DLC_DIR"
fi

echo "[3/7] Creating Python 3.11 venv..."
python3.11 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

echo "[4/7] Upgrading pip..."
pip install --upgrade pip

echo "[5/7] Installing Deep-Live-Cam dependencies..."
pip install -r requirements.txt

# GFPGAN + BasicSR compatibility (from official install guide)
pip install git+https://github.com/xinntao/BasicSR.git@master
pip uninstall gfpgan -y
pip install git+https://github.com/TencentARC/GFPGAN.git@master

echo "[6/7] Installing PyTorch with CUDA 12.8 support..."
pip install -U torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

echo "[7/7] Installing ONNX Runtime GPU + pyvirtualcam..."
pip uninstall onnxruntime onnxruntime-gpu -y
pip install onnxruntime-gpu==1.23.2
pip install pyvirtualcam

echo ""
echo "=== Setup Complete ==="
echo ""
echo "To run Deep-Live-Cam with GPU acceleration:"
echo "  cd $DLC_DIR"
echo "  source venv/bin/activate"
echo "  python run.py --execution-provider cuda"
echo ""
echo "The virtual camera will appear at /dev/video10 (card label: DeepLiveCam)"
echo "Use Chromium (NOT Firefox) for any web-based camera flow."
echo ""
echo "First run will download models (~300MB)."