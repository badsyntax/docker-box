version: '3.8'

services:
  registry:
    image: registry:{{ DOCKER_REGISTRY_VERSION }}
    volumes:
      - data:/var/lib/registry
    networks:
      - {{ TRAEFIK_NETWORK }}
    healthcheck:
      test:
        [
          'CMD',
          'wget',
          '-q',
          '--tries=1',
          '--spider',
          'http://localhost:5000/v2',
        ]
    environment:
      - REGISTRY_HTTP_ADDR=0.0.0.0:5000
    deploy:
      replicas: 2
      labels:
        - 'traefik.http.middlewares.docker-registry-auth.basicauth.users={{ DOCKER_REGISTRY_USER_PASSWORD }}'
        - 'traefik.http.routers.docker-registry-secure.middlewares=docker-registry-auth'
        - 'traefik.http.middlewares.docker-registry-headers.headers.customrequestheaders.Docker-Distribution-Api-Version=registry/2.0'
        - 'traefik.http.routers.docker-registry.rule=Host(`{{ DOCKER_REGISTRY_HOST }}`)'
        - 'traefik.http.routers.docker-registry.entrypoints=web'
        - 'traefik.http.services.docker-registry-service.loadbalancer.server.port=5000'
        {%- if ENABLE_TLS == 'y' %}
        - 'traefik.http.routers.docker-registry-secure.entrypoints=websecure'
        - 'traefik.http.routers.docker-registry-secure.rule=Host(`{{ DOCKER_REGISTRY_HOST }}`)'
        - 'traefik.http.routers.docker-registry-secure.tls.certresolver=letsencrypt'
        {%- endif %}
        {%- if ENABLE_HTTPS_REDIRECTION == 'y' %}
        - 'traefik.http.middlewares.docker-registry-redirectscheme.redirectscheme.permanent=true'
        - 'traefik.http.middlewares.docker-registry-redirectscheme.redirectscheme.scheme=https'
        - 'traefik.http.routers.docker-registry.middlewares=docker-registry-redirectscheme'
        {%- endif %}

volumes:
  data:

networks:
  {{ TRAEFIK_NETWORK }}:
    external: true
