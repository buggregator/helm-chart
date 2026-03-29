# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Helm chart** for deploying [Buggregator](https://buggregator.dev) on Kubernetes. Buggregator is a lightweight, self-hosted debugging server for PHP applications that aggregates Sentry, Ray, VarDumper, Monolog, SMTP, HTTP Dumps, XHProf Profiler, and Inspector into a single platform.

The chart deploys the container image `ghcr.io/buggregator/server` which bundles RoadRunner (Go-based PHP app server), Centrifugo (WebSocket), Nginx (reverse proxy), and DoltDB (embedded MySQL-compatible database).

## Chart Structure

```
helm-chart/
├── Chart.yaml                  # Chart metadata (name, version, appVersion)
├── values.yaml                 # All configurable parameters with defaults
├── values-external-db.yaml     # Example: external PostgreSQL
├── values-sso.yaml             # Example: SSO + external DB + Ingress
├── .helmignore
└── templates/
    ├── _helpers.tpl             # Template helpers (names, labels, secret refs)
    ├── deployment.yaml          # Main Deployment with all env vars
    ├── service.yaml             # ClusterIP Service exposing all ports
    ├── ingress.yaml             # Optional Ingress for web UI
    ├── secret.yaml              # Secrets (encrypter key, DB password, auth creds)
    ├── serviceaccount.yaml      # Optional ServiceAccount
    ├── pvc.yaml                 # PVC for /app/runtime (attachments, profiles)
    ├── servicemonitor.yaml      # Optional Prometheus ServiceMonitor
    └── NOTES.txt                # Post-install instructions
```

## Deployment Modes

The chart supports three deployment modes controlled by values:

1. **Standalone** (`persistence.driver=cache`) — Default. Uses embedded DoltDB. Single replica only. No external database needed.

2. **External database** (`persistence.driver=db`) — Connects to PostgreSQL or MySQL via `externalDatabase.*` values. Required for multi-replica setups.

3. **With SSO** (`auth.enabled=true`) — Adds Auth0 or Kinde authentication. Configured via `auth.*` values.

## Key Architecture Details

- **Container ports**: 8082 (HTTP via nginx), 1025 (SMTP), 9912 (VarDumper), 9913 (Monolog), 9914 (Profiler), 2112 (Prometheus metrics)
- **Service ports**: Mapped from container ports, default service port for HTTP is 8000 → 8082
- **Internal services**: RoadRunner, Centrifugo, Nginx, and optionally DoltDB all run inside the same container managed by RoadRunner's service plugin
- **Runtime storage**: `/app/runtime` needs persistence for attachments (SMTP files, HTTP dumps) and XHProf profiles
- **Health checks**: HTTP GET on port 8082 (the `http` named port)
- **Secrets**: Three secret resources — app (encrypter key), db (password), auth (client ID/secret). Each supports `existingSecret` to reference pre-created secrets.

## Common Tasks

### Validate templates locally

```bash
helm template test ./helm-chart
helm template test ./helm-chart -f helm-chart/values-external-db.yaml
helm template test ./helm-chart -f helm-chart/values-sso.yaml
```

### Lint the chart

```bash
helm lint ./helm-chart
helm lint ./helm-chart -f helm-chart/values-external-db.yaml
```

### Install / upgrade

```bash
helm install buggregator ./helm-chart
helm upgrade buggregator ./helm-chart --set roadrunner.http.numWorkers=4
```

## Environment Variables Reference

The Deployment template sets environment variables on the container. Key mappings:

| values.yaml path | Environment variable | Purpose |
|---|---|---|
| `app.env` | `APP_ENV` | production / local |
| `app.debug` | `DEBUG` | Enable debug output |
| `persistence.driver` | `PERSISTENCE_DRIVER` | cache or db |
| `externalDatabase.*` | `DB_DRIVER`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` | External DB connection |
| `roadrunner.http.numWorkers` | `RR_HTTP_NUM_WORKERS` | HTTP concurrency |
| `roadrunner.jobs.numWorkers` | `RR_JOBS_NUM_WORKERS` | Queue concurrency |
| `roadrunner.centrifuge.numWorkers` | `RR_CENTRIFUGE_NUM_WORKERS` | WebSocket concurrency |
| `roadrunner.logLevel` | `RR_LOG_LEVEL` | RoadRunner log verbosity |
| `auth.enabled` | `AUTH_ENABLED` | Toggle SSO |
| `auth.provider` | `AUTH_PROVIDER` | auth0 / kinde |
| `supportedEvents` | `CLIENT_SUPPORTED_EVENTS` | Which debug event types to accept |

## Guidelines for Modifications

- Always keep secrets in `secret.yaml` with `existingSecret` support for production use.
- The container runs multiple internal services (RoadRunner, Centrifugo, Nginx, Dolt) — do not split them into separate pods; they communicate via localhost.
- When adding new environment variables, check the server's `.env.sample` and `.rr-prod.yaml` for the full list of available options.
- Database is intentionally NOT deployed by this chart — users provide their own via `externalDatabase.*`.
- The embedded DoltDB mode (`persistence.driver=cache`) does not support multiple replicas because DoltDB runs inside each container independently.
