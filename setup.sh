#!/usr/bin/env bash
###################
# setup.sh
#

set -o errexit
set -o nounset
set -o pipefail

GREEN='\033[0;32m'
NC='\033[0m'
DOCKER_BOX_PATH="$HOME/docker-box"

function log() {
  echo
  echo -e "➡ ${GREEN}${1}${NC}"
  echo
}

log "Installing git..."

apt-get update -qq
apt-get -qqy install git

if [ ! -d "$DOCKER_BOX_PATH" ]; then
  log "Downloading docker-box..."
  git clone \
    --depth 1 \
    https://github.com/badsyntax/docker-box \
    "$DOCKER_BOX_PATH"
fi

log "Updating docker-box..."
cd "$DOCKER_BOX_PATH"
git pull

./docker-box.sh
