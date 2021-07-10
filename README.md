# docker-box

A lightweight docker application platform for single servers that gives you:

- docker swarm
- docker registry
- portainer
- traefik
- tls with letsencrypt (optional)

See [examples/nginx-app](./examples/nginx-app) for a real-world example.

## Installation

### Overview

`docker-box` first installs portainer as a swarm stack, then installs `traefix` and `docker-registry` using the `portainer` API (using the `primary` endpoint), allowing you to manage the `traefix` and `docker-registry` stacks with portainer.

### System Requirements

You need a fresh install of Ubuntu 20.04. _This is the only supported OS version._

### DNS Setup

Create a wildcard `A` (ipv4) record to point `*.docker-box.example.com` to your server.

### Install

Run the following script to install:

```bash
curl -s https://raw.githubusercontent.com/badsyntax/docker-box/master/setup.sh | sudo -E bash
```

It is safe to re-run the above script after initial installation as `docker-box` will not overwrite any existing config files.

## Usage

Some general guidelines:

- Use multiple service replicas to ensure zero downtime service deploys
- Use service healthchecks to allow docker swarm to route to healthy containers

## FAQ

<details><summary>How can I update the portainer stack?</summary>
  
Edit `/root/docker-box/conf/portainer-stack.yml` and update the stack with `docker stack deploy -c "/root/docker-box/conf/portainer-stack.yml" portainer` (or re-run the intallation script).
  
</details>

<details><summary>How can I update the traefik config?</summary>

By default `traefik` config is set in the stack file as cli flags, but `/etc/traefik` is also mounted as a volume, so you have 2 options:

1. Update the cli flags in the `traefik` stack file, or
2. Create a config file at location `/var/lib/docker/volumes/traefik_etc/_data/traefik.yml`

</details>
