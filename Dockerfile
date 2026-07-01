FROM docker.io/searxng/searxng:latest@sha256:6c1e8797ba29a47d575dea4805e3138976bfe1333fab630418de03930bd14803

COPY settings.yml /etc/searxng/settings.yml

EXPOSE 8080
