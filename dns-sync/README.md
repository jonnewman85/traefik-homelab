# dns-sync: Traefik → Pi-hole DNS Sync

A custom Python script that automatically syncs Traefik router hostnames to [Pi-hole v6](https://pi-hole.net/) local DNS records. Every service routed through Traefik automatically gets a DNS entry pointing to the Traefik host — no manual DNS configuration needed.

**Standalone repo:** [jonmilele/traefik-pihole-sync](https://github.com/jonmilele/traefik-pihole-sync)

## How It Works

```
┌─────────────┐     poll routers     ┌───────────────┐
│  Traefik    │◄─────────────────────│  sync.py      │
│  API :8080  │     every 2 min      │  (cron job)   │
└─────────────┘                      └───────┬───────┘
                                             │
                              compare hash   │
                              with cache     │
                                             │
                    ┌────────────────────────┬┘
                    │ if changed             │
                    ▼                        ▼
           ┌──────────────┐        ┌──────────────┐
           │  Pi-hole 1   │        │  Pi-hole 2   │
           │  192.0.2.100 │        │  192.0.2.101 │
           └──────────────┘        └──────────────┘
```

1. **Poll** — Queries `GET /api/http/routers` from the Traefik API
2. **Extract** — Parses `Host(...)` rules from each router, filtering out `internal` providers
3. **Hash** — Computes a SHA256 hash of all hostnames. If unchanged from last run, exits early
4. **Backup** — Saves the current Pi-hole DNS state to a timestamped JSON file
5. **Diff & Sync** — Compares desired hostnames against current Pi-hole entries, adds/removes as needed
6. **Conflict resolution** — If a hostname points to a different IP, the old entry is replaced
7. **Cache** — Saves the new hash so the next run can detect changes

## Features

- **Zero dependencies** — Pure Python 3 stdlib (no pip packages)
- **Multi-instance Pi-hole** — Syncs to multiple Pi-hole v6 instances
- **Per-instance passwords** — Different password per Pi-hole via env vars
- **Change detection** — Only updates Pi-hole when routes actually change
- **Backup & rollback** — Automatic pre-sync backups, with `--rollback` to restore
- **Dry run** — Preview changes without applying them
- **Conflict handling** — Detects and replaces stale DNS entries pointing to wrong IPs
- **Retry with backoff** — Retries failed API calls with exponential backoff
- **Structured exit codes** — 0 (success), 1 (config error), 2 (Traefik error), 3 (Pi-hole error)

## Setup

### 1. Install the script

```bash
sudo mkdir -p /opt/traefik-dns-sync/backups
sudo cp sync.py sync.sh /opt/traefik-dns-sync/
sudo chmod +x /opt/traefik-dns-sync/sync.sh
```

### 2. Configure environment

```bash
sudo cp .env.example /opt/traefik-dns-sync/.env
sudo chmod 600 /opt/traefik-dns-sync/.env
# Edit .env with your values
sudo nano /opt/traefik-dns-sync/.env
```

### 3. Add cron job

```bash
sudo crontab -e
# Add:
*/2 * * * * /opt/traefik-dns-sync/sync.sh >> /var/log/traefik-dns-sync.log 2>&1
```

## Configuration

All configuration is via environment variables in `.env`:

| Variable | Default | Description |
|----------|---------|-------------|
| `TRAEFIK_URL` | `http://127.0.0.1:8080` | Traefik API base URL |
| `TRAEFIK_IP` | *(required)* | IP address of your Traefik instance |
| `PIHOLE_HOSTS` | *(required)* | Comma-separated Pi-hole IPs |
| `PIHOLE_PASSWORD` | *(required)* | Default Pi-hole admin password |
| `PIHOLE_PASSWORD_<IP>` | — | Per-instance password (IP with dots replaced by underscores) |
| `PIHOLE_SCHEME` | `https` | `http` or `https` |
| `PIHOLE_PORT` | `443` | Pi-hole web port |
| `EXCLUDE_ROUTERS` | — | Comma-separated router names to skip |
| `EXCLUDE_PROVIDERS` | `internal` | Comma-separated providers to skip |
| `CACHE_FILE` | `/opt/traefik-dns-sync/.last_hash` | Path to hash cache |
| `BACKUP_DIR` | `/opt/traefik-dns-sync/backups` | Backup directory |
| `BACKUP_RETAIN` | `10` | Number of backups to keep per Pi-hole |
| `DRY_RUN` | `false` | Preview mode |
| `DEBUG` | — | Enable debug logging |
| `RETRY_ATTEMPTS` | `3` | API retry attempts |
| `RETRY_BACKOFF_BASE` | `2.0` | Exponential backoff base (seconds) |

## Usage

### Normal sync (via cron)
```bash
/opt/traefik-dns-sync/sync.sh
```

### Dry run (preview changes)
```bash
DRY_RUN=true python3 sync.py
```

### Debug mode
```bash
DEBUG=1 python3 sync.py
```

### List backups
```bash
python3 sync.py --list-backups
```

### Rollback to a backup
```bash
# Preview first
DRY_RUN=true python3 sync.py --rollback /opt/traefik-dns-sync/backups/192.0.2.100_2026-02-20T120000Z.json

# Apply
python3 sync.py --rollback /opt/traefik-dns-sync/backups/192.0.2.100_2026-02-20T120000Z.json
```

## Pi-hole v6 API

The script uses the Pi-hole v6 REST API:

- `POST /api/auth` — Authenticate and get a session ID
- `GET /api/config/dns/hosts` — List current local DNS entries
- `PUT /api/config/dns/hosts/{entry}` — Add a DNS entry
- `DELETE /api/config/dns/hosts/{entry}` — Remove a DNS entry
- `DELETE /api/auth` — Log out

Each entry is formatted as `"IP hostname"` (e.g. `"192.0.2.10 bitwarden.example.com"`).

## References

- [Pi-hole v6 API Documentation](https://docs.pi-hole.net/api/) — REST API reference
- [Pi-hole v6 Authentication](https://docs.pi-hole.net/api/auth/) — Session-based auth (SID) used by the script
- [Traefik API](https://doc.traefik.io/traefik/operations/api/) — The `/api/http/routers` endpoint polled by the script
