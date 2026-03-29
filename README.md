# Buggregator Helm Chart

A Helm chart for deploying [Buggregator](https://buggregator.dev) — a lightweight, self-hosted debugging server for PHP applications — on Kubernetes.

Buggregator aggregates multiple debugging tools (Sentry, Ray, VarDumper, Monolog, SMTP, HTTP Dumps, XHProf, Inspector) into a single platform with a real-time web UI.

## Prerequisites

- Kubernetes 1.23+
- Helm 3.x

## Quick Start

```bash
helm install buggregator ./helm-chart
```

Open the web UI:

```bash
kubectl port-forward svc/buggregator 8000:8000
```

Then navigate to http://localhost:8000.

## Installation

### Standalone (embedded database)

The simplest setup — uses the built-in DoltDB, no external dependencies:

```bash
helm install buggregator ./helm-chart
```

This is suitable for development, testing, or single-replica production use.

### With external PostgreSQL

For production or multi-replica setups, use an external database:

```bash
helm install buggregator ./helm-chart \
  --set persistence.driver=db \
  --set externalDatabase.driver=pgsql \
  --set externalDatabase.host=my-postgres.database.svc \
  --set externalDatabase.port=5432 \
  --set externalDatabase.database=buggregator \
  --set externalDatabase.username=buggregator \
  --set externalDatabase.password=changeme
```

Or use a values file:

```bash
helm install buggregator ./helm-chart -f values-external-db.yaml
```

MySQL is also supported — set `externalDatabase.driver=mysql` and `externalDatabase.port=3306`.

> **Note:** Buggregator does not create the database itself. You must create it beforehand. Tables are created automatically via migrations on startup.

### With SSO authentication

Enable SSO to restrict access to the web UI:

```bash
helm install buggregator ./helm-chart \
  --set auth.enabled=true \
  --set auth.provider=auth0 \
  --set auth.providerUrl=https://your-tenant.auth0.com \
  --set auth.clientId=YOUR_CLIENT_ID \
  --set auth.clientSecret=YOUR_CLIENT_SECRET \
  --set auth.callbackUrl=https://buggregator.example.com/auth/sso/callback
```

Supported providers: [Auth0](https://auth0.com/) and [Kinde](https://kinde.com/).

A full example combining SSO, external database, and Ingress is available in `values-sso.yaml`.

### With Ingress

```bash
helm install buggregator ./helm-chart \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.hosts[0].host=buggregator.example.com \
  --set ingress.hosts[0].paths[0].path=/ \
  --set ingress.hosts[0].paths[0].pathType=Prefix
```

## Connecting your PHP application

Once deployed, configure your PHP application to send data to Buggregator using the Kubernetes service name.

Assuming the release is named `buggregator` in the `default` namespace:

```dotenv
# Sentry
SENTRY_LARAVEL_DSN=http://sentry@buggregator.default.svc:8000/1

# Ray
RAY_HOST=buggregator.default.svc
RAY_PORT=8000

# SMTP
MAIL_MAILER=smtp
MAIL_HOST=buggregator.default.svc
MAIL_PORT=1025

# VarDumper
VAR_DUMPER_FORMAT=server
VAR_DUMPER_SERVER=buggregator.default.svc:9912

# Monolog (SocketHandler)
LOG_CHANNEL=socket
LOG_SOCKET_URL=buggregator.default.svc:9913
```

## Ports

| Port | Protocol | Module | Description |
|------|----------|--------|-------------|
| 8000 | HTTP | Sentry, Ray, Inspector, HTTP Dumps, XHProf | Web UI + HTTP-based event ingestion |
| 1025 | SMTP | Fake SMTP Server | Captures outgoing emails |
| 9912 | TCP | Symfony VarDumper | Receives `dump()` / `dd()` output |
| 9913 | TCP | Monolog | Receives log records via SocketHandler |
| 9914 | TCP | XHProf Profiler | Receives profiling data |
| 2112 | HTTP | Metrics | Prometheus-compatible metrics endpoint |

## Configuration Reference

### Application

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas (>1 requires external DB) | `1` |
| `image.repository` | Container image | `ghcr.io/buggregator/server` |
| `image.tag` | Image tag (defaults to `appVersion`) | `""` |
| `app.env` | Application environment | `production` |
| `app.debug` | Enable debug mode | `false` |
| `app.encrypterKey` | Encryption key (auto-generated if empty) | `""` |
| `app.existingSecret` | Existing secret name (key: `encrypter-key`) | `""` |

### Persistence / Database

| Parameter | Description | Default |
|-----------|-------------|---------|
| `persistence.driver` | `cache` (embedded DoltDB) or `db` (external) | `cache` |
| `externalDatabase.driver` | Database driver: `pgsql` or `mysql` | `pgsql` |
| `externalDatabase.host` | Database host | `""` |
| `externalDatabase.port` | Database port | `5432` |
| `externalDatabase.database` | Database name | `buggregator` |
| `externalDatabase.username` | Database username | `buggregator` |
| `externalDatabase.password` | Database password | `""` |
| `externalDatabase.existingSecret` | Existing secret (key: `db-password`) | `""` |

### Authentication (SSO)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `auth.enabled` | Enable SSO | `false` |
| `auth.provider` | SSO provider: `auth0` or `kinde` | `auth0` |
| `auth.providerUrl` | Provider URL | `""` |
| `auth.clientId` | OAuth client ID | `""` |
| `auth.clientSecret` | OAuth client secret | `""` |
| `auth.callbackUrl` | OAuth callback URL | `""` |
| `auth.scopes` | OAuth scopes | `openid,email,profile` |
| `auth.existingSecret` | Existing secret (keys: `client-id`, `client-secret`) | `""` |

### RoadRunner

| Parameter | Description | Default |
|-----------|-------------|---------|
| `roadrunner.http.numWorkers` | HTTP worker pool size | `2` |
| `roadrunner.jobs.numWorkers` | Job queue worker pool size | `2` |
| `roadrunner.centrifuge.numWorkers` | WebSocket worker pool size | `2` |
| `roadrunner.logLevel` | Log level: `error`, `warn`, `info`, `debug` | `warn` |
| `roadrunner.logEncoding` | Log format: `json` or `console` | `json` |
| `roadrunner.logMode` | Log mode: `production`, `development`, `raw` | `production` |
| `roadrunner.cors.allowedOrigin` | CORS allowed origins | `*` |
| `roadrunner.cors.allowedHeaders` | CORS allowed headers | `*` |
| `roadrunner.cors.allowCredentials` | CORS allow credentials | `true` |

### Service & Ingress

| Parameter | Description | Default |
|-----------|-------------|---------|
| `service.type` | Service type | `ClusterIP` |
| `service.httpPort` | Web UI port | `8000` |
| `service.smtpPort` | SMTP port | `1025` |
| `service.varDumperPort` | VarDumper port | `9912` |
| `service.monologPort` | Monolog port | `9913` |
| `service.profilerPort` | Profiler port | `9914` |
| `service.metricsPort` | Metrics port | `2112` |
| `ingress.enabled` | Enable Ingress | `false` |
| `ingress.className` | Ingress class name | `""` |

### Storage & Monitoring

| Parameter | Description | Default |
|-----------|-------------|---------|
| `storage.enabled` | Enable PVC for runtime data | `true` |
| `storage.size` | PVC size | `5Gi` |
| `storage.storageClassName` | Storage class | `""` |
| `metrics.serviceMonitor.enabled` | Enable Prometheus ServiceMonitor | `false` |
| `metrics.serviceMonitor.interval` | Scrape interval | `30s` |
| `supportedEvents` | Enabled event types | `http-dump,inspector,...` |

## Example Values Files

- **`values-external-db.yaml`** — External PostgreSQL with tuned workers
- **`values-sso.yaml`** — Full production setup: SSO + external DB + Ingress + TLS

## Uninstall

```bash
helm uninstall buggregator
```

> **Note:** The PVC for runtime data is not deleted automatically. Remove it manually if needed:
> ```bash
> kubectl delete pvc buggregator-runtime
> ```
