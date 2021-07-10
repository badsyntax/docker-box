#!/usr/bin/env bash
###########################################
# docker-box.sh
#
# A lightweight docker application platform.
#
# By Richard Willis <willis.rh@gmail.com>
###########################################

set -o errexit
set -o nounset
set -o pipefail

ARCH=$(dpkg --print-architecture)

export DEBIAN_FRONTEND=noninteractive

PORTAINER_VERSION="linux-${ARCH}"
TRAEFIK_NETWORK="traefik-public"
TRAEFIK_VERSION="latest"
DOCKER_REGISTRY_VERSION="latest"
ACME_STORAGE="/letsencrypt/acme.json"
# export DOCKER_VOLUMES_PATH="/var/lib/docker/volumes"

DOCKER_BOX_PATH="$HOME/docker-box"
DOCKER_BOX_DATA_PATH="$DOCKER_BOX_PATH/setup"
DOCKER_BOX_HOST="docker-box.example.com"
DOCKER_REGISTRY_USERNAME="richard"
CERTIFICATE_EMAIL="email@example.com"
PORTAINER_ADMIN_PASSWORD=""
ENABLE_TLS="n"
ENABLE_HTTPS_REDIRECTION="n"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

function log() {
  echo
  echo -e "➡ ${GREEN}${1}${NC}"
  echo
}

function log_success() {
  echo
  echo -e "✅ ${GREEN}${1}${NC}"
  echo
}

function log_warn() {
  echo
  echo -e "⚠️ ${YELLOW}${1}${NC}"
  echo
}

function log_error() {
  echo
  echo -e "⚠️ ${RED}ERROR: ${1}${NC}"
  echo
}

function get-input() {
  declare MESSAGE="$1" DEFAULT="$2"
  shift 2
  DEFAULT_MSG=""
  if [ -n "$DEFAULT" ]; then
    DEFAULT_MSG=" [$DEFAULT]"
  fi
  read -rp "$MESSAGE""$DEFAULT_MSG: " "$@" input </dev/tty
  if [[ -z "$input" ]]; then
    echo "$DEFAULT"
  else
    echo "$input"
  fi
}

echo
echo -en "➡ ${GREEN}Running preflight checks...${NC}"

if [ "$OSTYPE" != "linux-gnu" ]; then
  log_error "Wrong OS type: $OSTYPE"
  exit 1
fi

# shellcheck disable=SC1091
OS_NAME=$(
  . /etc/os-release
  echo "$NAME"
)
if [ "${OS_NAME}" != "Ubuntu" ]; then
  log_error "Wrong OS: ${OS_NAME}"
  exit 1
fi

# shellcheck disable=SC1091
OS_VERSION=$(
  . /etc/os-release
  echo "$VERSION_ID"
)
if [ "${OS_VERSION}" != "20.04" ]; then
  log_error "Wrong Ubuntu version: ${OS_VERSION}"
  exit 1
fi

echo -e "${GREEN}OK${NC}"

log "Installing setup packages..."

apt-get -qq update
apt-get install -yqq apache2-utils

log "Docker-Box setup"

if [ -f "$DOCKER_BOX_DATA_PATH" ]; then
  # shellcheck source=/dev/null
  source "$DOCKER_BOX_DATA_PATH"
fi

DOCKER_BOX_HOST=$(get-input "Docker Box hostname" "$DOCKER_BOX_HOST")
PORTAINER_ADMIN_PASSWORD=$(get-input "Portainer administrator password" "" -s)
echo
DOCKER_REGISTRY_USERNAME=$(get-input "Docker Registry username" "$DOCKER_REGISTRY_USERNAME")
echo "Docker registry password"
DOCKER_REGISTRY_USER_PASSWORD=$(htpasswd -nB "$DOCKER_REGISTRY_USERNAME" | sed -e s/\\$/\\$\\$/g)
ENABLE_TLS=$(get-input "Enable TLS? (y/n)" "$ENABLE_TLS")
ENABLE_TLS=$(echo "$ENABLE_TLS" | tr '[:upper:]' '[:lower:]')

if [ "$ENABLE_TLS" = 'y' ]; then
  CERTIFICATE_EMAIL=$(get-input "Email for certificates" "$CERTIFICATE_EMAIL")
  ENABLE_HTTPS_REDIRECTION=$(get-input "Enable HTTPS redirection? (y/n)" "$ENABLE_HTTPS_REDIRECTION")
  ENABLE_HTTPS_REDIRECTION=$(echo "$ENABLE_HTTPS_REDIRECTION" | tr '[:upper:]' '[:lower:]')
else
  ENABLE_HTTPS_REDIRECTION="n"
fi

true >"$DOCKER_BOX_DATA_PATH"
{
  echo "export DOCKER_BOX_HOST=$DOCKER_BOX_HOST"
  echo "export DOCKER_REGISTRY_USERNAME=$DOCKER_REGISTRY_USERNAME"
  echo "export ENABLE_TLS=$ENABLE_TLS"
  echo "export ENABLE_HTTPS_REDIRECTION=$ENABLE_HTTPS_REDIRECTION"
  echo "export CERTIFICATE_EMAIL=$CERTIFICATE_EMAIL"
} >>"$DOCKER_BOX_DATA_PATH"

# shellcheck source=/dev/null
source "$DOCKER_BOX_DATA_PATH"

# Template variables
export CERTIFICATE_EMAIL
export ENABLE_TLS
export ENABLE_HTTPS_REDIRECTION
export PORTAINER_VERSION
export TRAEFIK_NETWORK
export TRAEFIK_VERSION
export DOCKER_REGISTRY_VERSION
export DOCKER_REGISTRY_USER_PASSWORD
export DOCKER_REGISTRY_HOST="registry.$DOCKER_BOX_HOST"
export TRAEFIK_HOST="traefik.$DOCKER_BOX_HOST"
export PORTAINER_HOST="portainer.$DOCKER_BOX_HOST"
export ACME_STORAGE

log "Upgrading packages..."
# # apt-get -yqq upgrade

apt-get -yqq install \
  apt-transport-https \
  ca-certificates \
  gnupg \
  curl \
  lsb-release \
  jq \
  python3-pip

pip3 install j2cli

log "Installing docker..."

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=${ARCH} signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null

apt-get -yqq update
apt-get -yqq install docker-ce docker-ce-cli containerd.io

log "Setting up docker swarm..."
if ! docker service ls 2>/dev/null; then
  docker swarm init
fi
docker node ls

log "Setting up acme storage volume..."

mkdir -p "$(dirname $ACME_STORAGE)"
touch "$ACME_STORAGE"
chmod 600 "$ACME_STORAGE"

log "Creating portainer secret..."
if ! docker secret inspect portainer-pass 2>/dev/null >/dev/null; then
  echo -n "$PORTAINER_ADMIN_PASSWORD" | docker secret create portainer-pass -
fi

log "Creating traefik docker network..."
if ! docker network inspect "${TRAEFIK_NETWORK}" 2>/dev/null >/dev/null; then
  docker network create --driver=overlay --attachable "${TRAEFIK_NETWORK}"
fi

log "Setting up portainer using version \"${PORTAINER_VERSION}\"..."

if [ ! -f "$DOCKER_BOX_PATH/conf/portainer-stack.yml" ]; then
  j2 "$DOCKER_BOX_PATH/conf/portainer-stack.yml.tpl" >"$DOCKER_BOX_PATH/conf/portainer-stack.yml"
else
  log_warn "portainer stack config already exists, not overwriting $DOCKER_BOX_PATH/conf/portainer-stack.yml"
fi

docker stack deploy -c "$DOCKER_BOX_PATH/conf/portainer-stack.yml" portainer

echo
echo -en "➡ ${GREEN}Waiting for portainer service to start...${NC}"

i=0
while true; do
  if docker run --net="$TRAEFIK_NETWORK" curlimages/curl:7.77.0 curl --fail portainer:9000 2>/dev/null >/dev/null; then
    break
  else
    ((i = i + 1))
  fi

  if [ "$i" -eq 20 ]; then
    echo
    log_error "Portainer service not healthy"
    exit 1
  fi

  echo -en "${GREEN}.${NC}"
  sleep 2
done

echo -e "${GREEN}OK${NC}"

log "Generating portainer API token..."

if ! PORTAINER_API_TOKEN=$(
  docker run --net=$TRAEFIK_NETWORK curlimages/curl:7.77.0 \
    curl \
    --fail \
    --silent \
    --header "Content-Type: application/json" \
    --header 'Accept: application/json' \
    --request POST \
    --data "{\"username\":\"admin\",\"password\":\"$PORTAINER_ADMIN_PASSWORD\"}" \
    portainer:9000/api/auth |
    jq --raw-output .jwt
); then
  log_error "Unable to generate portainer API token. Is the portainer admin password correct?"
  exit 1
fi

log "Getting primary portainer endpoint id..."

if ! PORTAINER_ENDPOINT_ID=$(
  docker run --net=$TRAEFIK_NETWORK curlimages/curl:7.77.0 \
    curl \
    --fail \
    --silent \
    --header "Authorization: Bearer $PORTAINER_API_TOKEN" \
    --header 'Accept: application/json' \
    --request GET \
    portainer:9000/api/endpoints | jq -e -c '.[] | select(.Name | contains("primary")) | .Id'
); then
  log_error "Unable to get primary portainer endpoint id"
fi

log "Getting swarm id..."

if ! PORTAINER_SWARM_ID=$(
  docker run --net=$TRAEFIK_NETWORK curlimages/curl:7.77.0 \
    curl \
    --fail \
    --silent \
    --header "Authorization: Bearer $PORTAINER_API_TOKEN" \
    --header 'Accept: application/json' \
    --request GET \
    portainer:9000/api/endpoints/$PORTAINER_ENDPOINT_ID/docker/swarm |
    jq --raw-output .ID
); then
  log_error "Unable to get swarm id"
  exit 1
fi

log "Creating traefik stack..."

if ! docker run --net=$TRAEFIK_NETWORK curlimages/curl:7.77.0 \
  curl \
  --fail \
  --silent \
  --header "Authorization: Bearer $PORTAINER_API_TOKEN" \
  --header 'Accept: application/json' \
  --request GET \
  portainer:9000/api/stacks | jq -e -c '.[] | select(.Name | contains("traefik"))' >/dev/null; then

  TRAEFIK_STACK=$(j2 "$DOCKER_BOX_PATH/conf/traefik-stack.yml.tpl" | jq --raw-input --slurp)

  if ! docker run --net=$TRAEFIK_NETWORK curlimages/curl:7.77.0 \
    curl \
    --fail \
    --silent \
    --header "Authorization: Bearer $PORTAINER_API_TOKEN" \
    --header "Content-Type: application/json" \
    --header 'Accept: application/json' \
    --request POST \
    --data "{\"name\":\"traefik\",\"stackFileContent\":$TRAEFIK_STACK,\"swarmID\":\"$PORTAINER_SWARM_ID\"}" \
    "portainer:9000/api/stacks?type=1&method=string&endpointId=$PORTAINER_ENDPOINT_ID" > \
    /dev/null; then
    log_error "Unable to create traefik stack"
    exit 1
  fi
else
  log_warn "traefik stack already exists, skipping..."
fi

log "Creating docker-registry stack..."

if ! docker run --net=$TRAEFIK_NETWORK curlimages/curl:7.77.0 \
  curl \
  --fail \
  --silent \
  --header "Authorization: Bearer $PORTAINER_API_TOKEN" \
  --header 'Accept: application/json' \
  --request GET \
  portainer:9000/api/stacks | jq -e -c '.[] | select(.Name | contains("docker-registry"))' >/dev/null; then

  DOCKER_REGISTRY_STACK=$(j2 "$DOCKER_BOX_PATH/conf/docker-registry-stack.yml.tpl" | jq --raw-input --slurp)

  if ! docker run --net=$TRAEFIK_NETWORK curlimages/curl:7.77.0 \
    curl \
    --fail \
    --silent \
    --header "Authorization: Bearer $PORTAINER_API_TOKEN" \
    --header "Content-Type: application/json" \
    --header 'Accept: application/json' \
    --request POST \
    --data "{\"name\":\"docker-registry\",\"stackFileContent\":$DOCKER_REGISTRY_STACK,\"swarmID\":\"$PORTAINER_SWARM_ID\"}" \
    "portainer:9000/api/stacks?type=1&method=string&endpointId=$PORTAINER_ENDPOINT_ID" > \
    /dev/null; then
    log_error "Unable to create docker-registry stack"
    exit 1
  fi
else
  log_warn "docker-registry stack already exists, skipping..."
fi

log "Pruning unused docker objects..."
docker system prune --force

log_success "Success! Your box is ready to use!"

[[ $ENABLE_TLS = "y" ]] && SCHEME="https" || SCHEME="http"

echo -e "➡ ${GREEN}Access portainer at: $SCHEME://$PORTAINER_HOST/${NC}"
echo -e "➡ ${GREEN}Access traefik at: $SCHEME://$TRAEFIK_HOST/${NC}"
echo -e "➡ ${GREEN}Access docker-registry at: $SCHEME://$DOCKER_REGISTRY_HOST/${NC}"

echo
echo "(It might take a little while for traefik to discover services.)"
echo
