# Traefik Proxmox Provider (Custom Fork)

A custom fork of [NX211/traefik-proxmox-provider](https://github.com/NX211/traefik-proxmox-provider) that adds **multi-node support** — the ability to configure multiple independent Proxmox hosts, each with their own API credentials.

**Full source:** [jonnewman85/traefik-proxmox-provider-multi-node](https://github.com/jonnewman85/traefik-proxmox-provider-multi-node)

## Why a Fork?

The upstream plugin supports a single Proxmox endpoint. My setup has two independent Proxmox nodes (not clustered), so the fork adds a `nodes` array to the config that lets you define multiple endpoints. It's fully backward-compatible — the legacy single-endpoint config still works.

## How It Works

The provider runs as a [Traefik local plugin](https://doc.traefik.io/traefik/plugins/local/) (compiled from source alongside Traefik, not fetched from the plugin catalog).

1. On startup, it connects to each configured Proxmox node via the API
2. Every `pollInterval` (5s), it queries each node for all VMs and containers
3. For each running VM/container, it reads the **Description** field looking for traefik labels
4. Labels are parsed and converted into Traefik dynamic configuration (routers + services)
5. The VM/container's IP is auto-detected via the QEMU guest agent or container network interfaces

When multiple nodes are configured (`multiCluster = true`), auto-generated router/service names are prefixed with the node name to avoid collisions (e.g. `pve-node-1-myapp-100` vs `pve-node-2-myapp-100`).

## Configuration

### Multi-node (my setup)

```yaml
providers:
  plugin:
    traefik-proxmox-provider:
      pollInterval: "5s"
      nodes:
        - name: "pve-node-1"
          apiEndpoint: "https://192.0.2.20:8006"
          apiTokenId: "root@pam!traefik_prod"
          apiToken: "YOUR_API_TOKEN"
          apiLogging: "warn"
          apiValidateSSL: "false"
        - name: "pve-node-2"
          apiEndpoint: "https://192.0.2.21:8006"
          apiTokenId: "root@pam!traefik_prod"
          apiToken: "YOUR_API_TOKEN"
          apiLogging: "info"
          apiValidateSSL: "false"
```

### Single-node (legacy, backward-compatible)

```yaml
providers:
  plugin:
    traefik-proxmox-provider:
      pollInterval: "5s"
      apiEndpoint: "https://192.0.2.20:8006"
      apiTokenId: "root@pam!traefik"
      apiToken: "YOUR_API_TOKEN"
      apiLogging: "info"
      apiValidateSSL: "false"
```

## Proxmox VM/Container Labels

Labels are placed in the **Description** field of a VM or container in the Proxmox web UI (or via the API). They follow the same format as Traefik Docker labels.

### Minimal example
```
traefik.enable=true
traefik.http.routers.myapp.rule=Host(`myapp.example.com`)
traefik.http.routers.myapp.entrypoints=websecure
traefik.http.services.myapp.loadbalancer.server.port=8080
```

### Full example with middlewares and TLS
```
traefik.enable=true
traefik.http.routers.myapp.rule=Host(`myapp.example.com`)
traefik.http.routers.myapp.entrypoints=websecure
traefik.http.routers.myapp.middlewares=security-headers@file
traefik.http.routers.myapp.tls=true
traefik.http.routers.myapp.tls.certresolver=default
traefik.http.services.myapp.loadbalancer.server.port=8080
traefik.http.services.myapp.loadbalancer.server.scheme=https
```

### Supported label options

**Router options:**
- `.rule` — Traefik routing rule (e.g. `Host(...)`)
- `.entrypoints` — Comma-separated entrypoints
- `.middlewares` — Comma-separated middleware references
- `.service` — Explicit service name (otherwise auto-generated)
- `.priority` — Router priority
- `.tls` — Enable TLS (`true`)
- `.tls.certresolver` — Certificate resolver name
- `.tls.options` — TLS options reference
- `.tls.domains` — Comma-separated domain list
- `.tls.domains[N].main` / `.tls.domains[N].sans` — Array-indexed domain config

**Service options:**
- `.loadbalancer.server.port` — Backend port
- `.loadbalancer.server.scheme` — `http` or `https`
- `.loadbalancer.server.url` — Direct URL override
- `.loadbalancer.server.ip` — Override auto-detected IP
- `.loadbalancer.passhostheader` — Pass Host header
- `.loadbalancer.healthcheck.path` / `.interval` / `.timeout`
- `.loadbalancer.sticky.cookie.name` / `.secure` / `.httponly`
- `.loadbalancer.responseforwarding.flushinterval`
- `.loadbalancer.serverstransport` — Reference a serversTransport

### Space-separated labels

The provider also supports space-separated labels on a single line (common with OCI containers in Proxmox):

```
traefik.enable=true traefik.http.routers.myapp.rule=Host(`myapp.example.com`) traefik.http.services.myapp.loadbalancer.server.port=80
```

## Installation

The plugin is installed as a local plugin at `/plugins-local/src/github.com/NX211/traefik-proxmox-provider/`:

```
/plugins-local/
└── src/
    └── github.com/
        └── NX211/
            └── traefik-proxmox-provider/
                ├── .traefik.yml
                ├── go.mod
                ├── go.sum
                ├── traefik_proxmox_provider.go
                ├── provider/
                │   ├── provider.go
                │   └── provider_test.go
                ├── internal/
                │   ├── client.go
                │   ├── types.go
                │   └── types_test.go
                └── vendor/
```

And referenced in the static config:

```yaml
experimental:
  localPlugins:
    traefik-proxmox-provider:
      moduleName: github.com/NX211/traefik-proxmox-provider
```

## Proxmox API Token Setup

On each Proxmox node, create an API token:

```bash
# Create a token for the root user (or a dedicated user with appropriate permissions)
pveum user token add root@pam traefik_prod --privsep 0

# The output will include the token value — save it securely
```

The token needs at minimum:
- `VM.Audit` — to list VMs and containers
- `VM.Monitor` — to read VM configs and network interfaces
- `Sys.Audit` — to list nodes and read version info

## References

- [NX211/traefik-proxmox-provider](https://github.com/NX211/traefik-proxmox-provider) — The upstream plugin this fork is based on
- [Traefik Local Plugins](https://doc.traefik.io/traefik/plugins/local/) — How local plugins are loaded by Traefik
- [Proxmox VE API](https://pve.proxmox.com/pve-docs/api-viewer/) — The Proxmox API used by the provider
- [Proxmox API Tokens](https://pve.proxmox.com/wiki/User_Management#pveum_tokens) — How to create and manage API tokens
