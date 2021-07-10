# Contributing

## Running Locally

Note we are running docker within docker using the host docker daemon.

```bash
docker run -it \
    -v $(pwd):/root/docker-box \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -p 80:80 \
    ubuntu:20.04 \
    /root/docker-box/docker-box.sh

# Remove containers and volumes
docker swarm leave --force
docker volume prune --force

# Or...
# docker stack rm $(docker stack ls --format "{{.Name}}")
```
