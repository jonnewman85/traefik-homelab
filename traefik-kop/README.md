# traefik-kop (Docker → Redis → Traefik)

[traefik-kop](https://github.com/jittering/traefik-kop) bridges Docker containers running on **other VMs and LXCs** (where Traefik is not running) into Traefik's routing configuration via Redis.

## The Problem

Traefik's Docker provider only works with containers on the same Docker host (or swarm). Since Traefik runs as a bare-metal systemd service (not in Docker), and Docker containers run on separate VMs and LXCs, we need a way to get their routing labels into Traefik.

## How It Works

```
Docker Host (VM or LXC)              Traefik Host (192.0.2.10)
┌─────────────────────┐              ┌─────────────────────────┐
│  Docker containers   │              │  Traefik                │
│  (with labels)       │              │    ↕                    │
│       ↓              │              │  Redis provider         │
│  traefik-kop         │──────────────│    ↕                    │
│  (watches Docker)    │   publishes  │  Redis (localhost:6379) │
│                      │   to Redis   │                         │
└─────────────────────┘              └─────────────────────────┘
```

1. **traefik-kop** runs alongside Docker on each VM or LXC
2. It watches the Docker socket for container start/stop events
3. When a container has `traefik.*` labels, kop translates them into Redis key/value pairs under the `traefik/` prefix
4. Traefik's built-in **Redis provider** reads these keys and creates routers/services
5. traefik-kop rewrites `localhost` / container-internal URLs to the Docker host's real IP

## Redis Setup

Redis runs on the Traefik host (192.0.2.10) and is accessible from the Docker hosts on the network.

Key Redis configuration:
```
bind 0.0.0.0
port 6379
requirepass YOUR_REDIS_PASSWORD
```

Redis modules loaded (for other purposes, not required by traefik-kop):
- ReJSON
- RedisBloom
- RedisTimeSeries
- RediSearch

## traefik-kop Configuration

On each Docker host (VM or LXC), traefik-kop runs as a container:

```yaml
services:
  traefik-kop:
    image: ghcr.io/jittering/traefik-kop:latest
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - REDIS_ADDR=192.0.2.10:6379
      - REDIS_PASS=YOUR_REDIS_PASSWORD
      - BIND_IP=<THIS_DOCKER_HOST_IP>
```

`BIND_IP` tells traefik-kop what IP to use when rewriting service URLs. This should be the Docker host's LAN IP so Traefik can reach the container ports.

## Docker Container Labels

Containers use standard Traefik Docker labels. traefik-kop translates them to Redis keys.

### Example: Bitwarden

```yaml
services:
  bitwarden:
    image: vaultwarden/server:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.bitwarden.rule=Host(`bitwarden.example.com`)"
      - "traefik.http.routers.bitwarden.entrypoints=websecure"
      - "traefik.http.routers.bitwarden.middlewares=security-headers@file"
      - "traefik.http.services.bitwarden.loadbalancer.server.port=80"
    ports:
      - "8080:80"
```

This creates Redis keys like:
```
traefik/http/routers/bitwarden/rule          = Host(`bitwarden.example.com`)
traefik/http/routers/bitwarden/entryPoints/0 = websecure
traefik/http/routers/bitwarden/middlewares/0 = security-headers@file
traefik/http/routers/bitwarden/service       = bitwarden
traefik/http/services/bitwarden/loadBalancer/servers/0/url = http://<BIND_IP>:8080
```

## Currently Published Services

These Docker containers are published to Traefik via traefik-kop → Redis:

| Service | Hostname |
|---------|----------|
| Bitwarden (Vaultwarden) | `bitwarden.example.com` |
| Piwigo | `piwigo.example.com` |
| HandBrake MKV | `handbrake-mkv.example.com` |
| qBittorrent | `qbittorrent.example.com` |
| qBittorrent (old) | `qbittorrent-old.example.com` |

## Debugging

Check what's in Redis:
```bash
redis-cli -a YOUR_REDIS_PASSWORD keys "traefik/*" | sort
```

Check a specific router rule:
```bash
redis-cli -a YOUR_REDIS_PASSWORD GET "traefik/http/routers/bitwarden/rule"
```

Check Traefik sees the routes:
```bash
curl -s http://127.0.0.1:8080/api/http/routers | python3 -m json.tool | grep -A2 '"provider": "redis"'
```

## References

- [traefik-kop](https://github.com/jittering/traefik-kop) — The tool that bridges Docker labels to Redis
- [Traefik Redis Provider](https://doc.traefik.io/traefik/providers/redis/) — Traefik's built-in Redis provider documentation
- [Traefik Docker Provider](https://doc.traefik.io/traefik/providers/docker/) — The provider traefik-kop replaces for remote hosts
