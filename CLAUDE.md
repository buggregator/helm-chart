# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Helm chart** for deploying [Buggregator](https://buggregator.dev) on Kubernetes. Buggregator v2.0 is a single Go binary (~30 MB) with an embedded SQLite database, web UI, and WebSocket server. No PHP runtime, no external services required.

The chart deploys the container image `ghcr.io/buggregator/server` which contains a single `buggregator` binary.

## Chart Structure

```
helm-chart/
├── Chart.yaml                  # Chart metadata (name, version, appVersion)
├── values.yaml                 # All configurable parameters with defaults
├── values-sso.yaml             # Example: SSO + persistent storage + Ingress
├── .helmignore
└── templates/
    ├── _helpers.tpl             # Template helpers (names, labels, secret refs)
    ├── deployment.yaml          # Main Deployment with all env vars
    ├── service.yaml             # ClusterIP Service exposing all ports
    ├── ingress.yaml             # Optional Ingress for web UI
    ├── secret.yaml              # Secrets (auth creds + JWT secret)
    ├── serviceaccount.yaml      # Optional ServiceAccount
    ├── pvc.yaml                 # PVC for /data (SQLite DB, attachments)
    ├── servicemonitor.yaml      # Optional Prometheus ServiceMonitor
    └── NOTES.txt                # Post-install instructions
```

## Key Architecture Details

- **Container ports**: 8000 (HTTP/WebSocket), 1025 (SMTP), 9912 (VarDumper), 9913 (Monolog)
- **Single binary**: The Go binary serves HTTP, WebSocket, and the embedded SPA frontend directly on port 8000
- **Database**: Embedded SQLite at `/data/buggregator.db` on the PVC by default; `:memory:` only with `storage.enabled=false`
- **One replica, Recreate**: SQLite has one writer and the volume is RWO; `replicaCount` other than 1 fails to render
- **Publishing**: tag `vX.Y.Z` (= Chart.yaml `version`) → `.github/workflows/release.yml` pushes `oci://ghcr.io/buggregator/helm-chart/buggregator:X.Y.Z` (the URL the docs and the server's update hint use)
- **Health checks**: HTTP GET on `/api/settings` port 8000 (public endpoint, no auth required)
- **Secrets**: Only auth secret (client-id, client-secret, jwt-secret) when SSO is enabled
- **Storage**: `/data` for SQLite database file and filesystem attachments

## Common Tasks

### Validate templates locally

```bash
helm template test ./helm-chart
helm template test ./helm-chart -f helm-chart/values-sso.yaml
```

### Lint the chart

```bash
helm lint ./helm-chart
helm lint ./helm-chart -f helm-chart/values-sso.yaml
```

### Install / upgrade

```bash
helm install buggregator ./helm-chart
helm upgrade buggregator ./helm-chart --set database.dsn=/data/buggregator.db
```

## Environment Variables Reference

| values.yaml path | Environment variable | Purpose |
|---|---|---|
| `database.dsn` | `DATABASE_DSN` | SQLite DSN (`:memory:` or file path) |
| `attachmentStorage.mode` | `STORAGE_MODE` | `memory` or `filesystem` |
| `attachmentStorage.path` | `STORAGE_PATH` | Directory for filesystem attachments |
| `cors.origins` | `CORS_ORIGINS` | CORS allowed origins |
| `supportedEvents` | `CLIENT_SUPPORTED_EVENTS` | Which event types to accept |
| `metrics.enabled` | `METRICS_ENABLED` | Enable Prometheus metrics |
| `metrics.addr` | `METRICS_ADDR` | Separate metrics server address |
| `mcp.enabled` | `MCP_ENABLED` | Enable MCP server |
| `mcp.transport` | `MCP_TRANSPORT` | MCP transport (`socket` or `http`) |
| `auth.enabled` | `AUTH_ENABLED` | Toggle SSO |
| `auth.provider` | `AUTH_PROVIDER` | auth0/google/github/keycloak/gitlab/oidc |
| `auth.jwtSecret` | `AUTH_JWT_SECRET` | JWT signing secret |

## Guidelines for Modifications

- The container runs a single Go binary — no nginx, no PHP, no external services.
- When adding new environment variables, check the server's `buggregator.yaml.example` and `internal/app/config.go`.
- Secrets are only created for auth (when `auth.enabled=true`). The database is embedded SQLite, no external DB secrets needed.
- Health checks use `/api/settings` which is always public (no auth middleware).
