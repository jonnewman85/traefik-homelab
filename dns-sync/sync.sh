#!/bin/bash
set -a
source /opt/traefik-dns-sync/.env
set +a
/usr/bin/python3 /opt/traefik-dns-sync/sync.py
