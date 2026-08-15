#!/usr/bin/env bash
# ===========================================
# Shrike AI Lab - Linux Host Bootstrap
# ===========================================
# Installs Docker Engine + Compose plugin + NVIDIA container runtime on Ubuntu/Debian.
# Run once on a fresh machine, then run ./scripts/setup.sh for service/model setup.

set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo "Run this script as a normal user (it will call sudo as needed)."
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required but not found."
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This script currently supports apt-based distros (Ubuntu/Debian)."
  exit 1
fi

echo "Updating apt metadata and installing base packages..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release jq

echo "Installing Docker official repository..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

source /etc/os-release
ARCH="$(dpkg --print-architecture)"
CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "Adding ${USER} to docker group..."
sudo usermod -aG docker "${USER}"

echo "Configuring NVIDIA container runtime (if NVIDIA GPU exists)..."
if command -v nvidia-smi >/dev/null 2>&1; then
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed "s#\$(ARCH)#${ARCH}#g" \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null

  sudo apt-get update
  sudo apt-get install -y nvidia-container-toolkit
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker
else
  echo "nvidia-smi not found. Skipping NVIDIA container toolkit setup."
fi

echo
echo "Bootstrap complete."
echo "Next steps:"
echo "  1) Open a new shell (or run: newgrp docker)"
echo "  2) cd /run/media/mhintermeister/secondary_drive/LocalProjects/shrike-ai-lab"
echo "  3) ./scripts/setup.sh"
echo "  4) make status"
