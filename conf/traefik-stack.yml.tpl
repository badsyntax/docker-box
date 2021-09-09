version: '3.8'

services:
  traefik:
    image: traefik:{{ TRAEFIK_VERSION }}
    ports:
      - target: 80
        published: 80
        mode: host
      - target: 443
        published: 443
        mode: host
    volumes:
      - '/var/run/docker.sock:/var/run/docker.sock:ro'
      - 'etc:/etc/traefik'
      {%- if ENABLE_TLS == 'y' %}
      - {{ ACME_STORAGE }}:{{ ACME_STORAGE }}
      {%- endif %}
    healthcheck:
      test: ['CMD', 'traefik', 'healthcheck', '--ping']
    command:
      - '--ping'
      - '--api.insecure=true'
      - '--providers.docker.swarmMode=true'
      - '--providers.docker.network={{ TRAEFIK_NETWORK }}'
      - '--entrypoints.web.address=:80'
      {%- if ENABLE_TLS == 'y' %}
      - '--entrypoints.websecure.address=:443'
      - '--certificatesresolvers.letsencrypt.acme.email={{ CERTIFICATE_EMAIL }}'
      - '--certificatesresolvers.letsencrypt.acme.storage={{ ACME_STORAGE }}'
      # - '--certificatesresolvers.letsencrypt.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory'
      - '--certificatesresolvers.letsencrypt.acme.tlschallenge=true'
      {%- endif %}
    networks:
      - {{ TRAEFIK_NETWORK }}
    deploy:
      replicas: 1
      labels:
        - 'traefik.http.routers.traefik.entrypoints=web'
        - 'traefik.http.routers.traefik.rule=Host(`{{ TRAEFIK_HOST }}`)'
        - 'traefik.http.services.traefik-service.loadbalancer.server.port=8080'
        {%- if ENABLE_TLS == 'y' %}
        - 'traefik.http.routers.traefik-secure.entrypoints=websecure'
        - 'traefik.http.routers.traefik-secure.rule=Host(`{{ TRAEFIK_HOST }}`)'
        - 'traefik.http.routers.traefik-secure.tls.certresolver=letsencrypt'
        {%- endif %}
        {%- if ENABLE_HTTPS_REDIRECTION == 'y' %}
        - 'traefik.http.middlewares.traefik-redirectscheme.redirectscheme.permanent=true'
        - 'traefik.http.middlewares.traefik-redirectscheme.redirectscheme.scheme=https'
        - 'traefik.http.routers.traefik.middlewares=traefik-redirectscheme'
        {%- endif %}

volumes:
  etc:

networks:
  {{ TRAEFIK_NETWORK }}:
    external: true
