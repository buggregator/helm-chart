# Buggregator Helm Chart

Deploys [Buggregator](https://buggregator.dev) on Kubernetes: one Go binary with an embedded SQLite database, web UI and WebSocket server. It receives Sentry, Ray, VarDumper, Monolog, SMTP, Inspector, profiler (XHProf) and HTTP dump events.

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8+ (OCI registries)
- A default StorageClass, or `storage.storageClassName`

## Install

```bash
helm install buggregator oci://ghcr.io/buggregator/helm-chart/buggregator
```

Open the web UI:

```bash
kubectl port-forward svc/buggregator 8000:8000
```

Then go to http://localhost:8000.

A specific chart version: add `--version 3.0.0`. A specific server image: `--set image.tag=2.11.0` (default: the chart's `appVersion`).

## Upgrade

```bash
helm upgrade buggregator oci://ghcr.io/buggregator/helm-chart/buggregator --reuse-values
```

The pod is replaced with the `Recreate` strategy: the old pod stops before the new one starts, because both would open the same SQLite file. Expect a few seconds of downtime.

## Data

By default a PersistentVolumeClaim (`storage.size`, 5Gi) is mounted at `/data`:

- the database: `/data/buggregator.db`
- attachments (SMTP attachments, HTTP dump files): `/data/storage`

With `storage.enabled=false` everything is kept in memory and lost on every restart.

Buggregator runs as **one replica**: SQLite has a single writer and the volume is ReadWriteOnce. Any other `replicaCount` fails to render.

## Authentication (SSO)

```bash
helm install buggregator oci://ghcr.io/buggregator/helm-chart/buggregator \
  --set auth.enabled=true \
  --set auth.provider=auth0 \
  --set auth.providerUrl=https://your-tenant.auth0.com \
  --set auth.clientId=YOUR_CLIENT_ID \
  --set auth.clientSecret=YOUR_CLIENT_SECRET \
  --set auth.callbackUrl=https://buggregator.example.com/auth/sso/callback
```

Providers: `auth0`, `google`, `github`, `keycloak`, `gitlab`, `oidc`.

The session signing key (`auth.jwtSecret`) is generated on install and kept across upgrades, so users stay signed in. Set it yourself, or keep all three values in your own secret with `auth.existingSecret` (keys `client-id`, `client-secret`, `jwt-secret`).

The key is kept by reading the release's secret from the cluster (`lookup`). Tools that only render templates (Argo CD, Flux with `helm template`) cannot read it and would make a new key on every sync: there set `auth.jwtSecret` or `auth.existingSecret`.

A full example with SSO, Ingress with TLS and metrics: [`values-sso.yaml`](values-sso.yaml).

## Connecting your application

Inside the cluster (release `buggregator`, namespace `default`):

| What | Address |
|---|---|
| Sentry DSN | `http://sentry@buggregator.default.svc:8000/1` |
| Ray | host `buggregator.default.svc`, port `8000` |
| SMTP | `buggregator.default.svc:1025` |
| VarDumper | `tcp://buggregator.default.svc:9912` |
| Monolog (socket handler) | `buggregator.default.svc:9913` |
| HTTP dumps, Inspector, profiler | `http://buggregator.default.svc:8000` |

An Ingress carries only HTTP (port 8000). SMTP, VarDumper and Monolog are TCP: reach them from outside the cluster with `service.type=LoadBalancer` or `NodePort`.

## Values

| Parameter | Description | Default |
|---|---|---|
| `image.repository` | Server image | `ghcr.io/buggregator/server` |
| `image.tag` | Image tag | chart `appVersion` |
| `database.dsn` | SQLite DSN | `/data/buggregator.db` with storage, else `:memory:` |
| `attachmentStorage.mode` | `filesystem` or `memory` | `filesystem` with storage, else `memory` |
| `attachmentStorage.path` | Attachments directory | `/data/storage` |
| `storage.enabled` | PVC at `/data` | `true` |
| `storage.size` | PVC size | `5Gi` |
| `storage.storageClassName` | Storage class | `""` (cluster default) |
| `cors.origins` | Allowed CORS origins | `*` |
| `supportedEvents` | Enabled event types (comma-separated) | all |
| `auth.enabled` | SSO | `false` |
| `auth.provider` | `auth0`, `google`, `github`, `keycloak`, `gitlab`, `oidc` | `oidc` |
| `auth.providerUrl`, `auth.clientId`, `auth.clientSecret`, `auth.callbackUrl`, `auth.scopes` | SSO settings | |
| `auth.jwtSecret` | Session signing key | generated once, kept |
| `auth.existingSecret` | Secret with `client-id`, `client-secret`, `jwt-secret` | `""` |
| `mcp.enabled`, `mcp.transport`, `mcp.addr`, `mcp.authToken` | MCP server for AI assistants | off |
| `metrics.enabled` | Prometheus `/metrics` | `false` |
| `metrics.addr` | Separate metrics address (e.g. `:9090`); empty = main port | `""` |
| `metrics.serviceMonitor.enabled` | Prometheus Operator ServiceMonitor | `false` |
| `service.type` | Service type | `ClusterIP` |
| `service.httpPort`, `smtpPort`, `varDumperPort`, `monologPort` | Service ports | `8000`, `1025`, `9912`, `9913` |
| `ingress.*` | Ingress for the web UI | off |
| `resources`, `nodeSelector`, `tolerations`, `affinity`, `podSecurityContext`, `securityContext` | Pod settings | empty |

See [`values.yaml`](values.yaml) for every option.

## Uninstall

```bash
helm uninstall buggregator
```

The PVC is deleted with the release. Back up `/data/buggregator.db` first if you need it.

## Releases

A tag `vX.Y.Z` equal to `version` in `Chart.yaml` publishes `oci://ghcr.io/buggregator/helm-chart/buggregator:X.Y.Z` and a GitHub release with the packaged chart.
