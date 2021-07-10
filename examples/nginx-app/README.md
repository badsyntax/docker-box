# An example nginx app

Deploy an nginx application to your docker-box.

## Manual Deployment

1. Build and push the docker image:

```bash
docker login registry.docker-box.example.com

docker buildx create --use

docker buildx build --platform linux/amd64,linux/arm64 \
  -t registry.docker-box.example.com/user/nginx-app:latest \
  --push .
```

2. Log into portainer and use the contents of [docker-compose.yml](./docker-compose.yml) to create a new stack
3. Once the stack is created access the app at https://nginx-app.example.com

## Continuous Deployment with GitHub Actions

The general flow is:

1. Build and push docker image
2. Call portainer service webhook to deploy new image version

### Setup

1. Create the stack in portainer (use the `Git Repository` build method to use your stack definition from your repository)
1. Navigate to the service you wish to deploy, enable the `Service webhook` and copy the `Service webhook` url
1. Add the `Service webhook` url as a secret (eg `DEPLOY_ENDPOINT`) to your GitHub repo
1. Add your docker-registry username as a secret (eg `DOCKER_REGISTRY_USERNAME`) to your GitHub Repo
1. Add your docker-registry password as a secret (eg `DOCKER_REGISTRY_PASSWORD`) to your GitHub Repo
1. Create the following GitHub Actions workflow file to build & deploy the app on any change to the `main` branch:

```yml
name: Deploy
on:
  push:
    branches:
      - main

jobs:
  publish-docker-image:
    name: Publish docker image
    runs-on: ubuntu-20.04
    steps:
      - uses: actions/checkout@v2.3.4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v1

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v1

      - name: Cache Docker layers
        uses: actions/cache@v2
        with:
          path: /tmp/.buildx-cache
          key: ${{ runner.os }}-buildx-${{ github.sha }}
          restore-keys: |
            ${{ runner.os }}-buildx-

      - name: Login to Docker Registry
        uses: docker/login-action@v1
        with:
          registry: registry.docker-box.example.com
          username: ${{ secrets.DOCKER_REGISTRY_USERNAME }}
          password: ${{ secrets.DOCKER_REGISTRY_PASSWORD }}

      - name: Build and push docker image
        uses: docker/build-push-action@v2
        with:
          context: .
          file: ./Dockerfile
          push: true
          platforms: linux/arm64,linux/amd64
          tags: registry.docker-box.example.com/${{ github.repository }}:latest
          cache-from: type=local,src=/tmp/.buildx-cache
          cache-to: type=local,dest=/tmp/.buildx-cache-new

      # Temp fix
      # https://github.com/docker/build-push-action/issues/252
      # https://github.com/moby/buildkit/issues/1896
      - name: Move cache
        run: |
          rm -rf /tmp/.buildx-cache
          mv /tmp/.buildx-cache-new /tmp/.buildx-cache

  deploy:
    name: Deploy app
    runs-on: ubuntu-20.04
    needs: [publish-docker-image]
    steps:
      - name: Deploy
        run: |
          curl --fail -X POST "$DEPLOY_ENDPOINT" || exit 1
        env:
          DEPLOY_ENDPOINT: '${{ secrets.DEPLOY_ENDPOINT }}'
```
