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

Old events can be deleted automatically: `retention.maxAge` (e.g. `7d`) and `retention.maxEvents`. Pinned events are kept.

## Projects, webhooks and other file settings

What has no value in this chart goes into `config`: its contents become `buggregator.yaml` (a ConfigMap passed with `--config`). Environment variables set by the chart take precedence over the file.

```yaml
config:
  projects:
    - key: shop
      name: Shop backend
  webhooks:
    - event: sentry
      url: https://hooks.example.com/buggregator
```

Any other server variable: `extraEnv` (list of `{name, value}` or `valueFrom`) and `envFrom`.

## Security

The pod runs as user 65532 (non-root) with a read-only root filesystem, all capabilities dropped and the RuntimeDefault seccomp profile. `fsGroup` makes the volume writable for that user, including files written by older releases that ran as root. `/tmp` is an `emptyDir`: the VarDumper parser is unpacked and run from there.

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

| HTTP proxy | `http://buggregator.default.svc:8080` |
| Xdebug (with `xdebug.enabled`) | `buggregator.default.svc:9003` |

An Ingress carries only HTTP (port 8000). SMTP, VarDumper, Monolog, the HTTP proxy and Xdebug are TCP: `tcpService.enabled=true` adds a second Service (`LoadBalancer` by default) with just those ports, so the web UI can stay behind the Ingress.

Behind ingress-nginx, raise the timeouts for the UI's WebSocket (`/connection/websocket`), closed after 60 s by default:

```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
```

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
| `database.maxOpenConns` | SQLite connection pool size | server default |
| `retention.maxAge` | Delete events older than this (`24h`, `7d`) | keep |
| `retention.maxEvents` | Keep at most this many events | no cap |
| `config` | Contents of `buggregator.yaml` (projects, webhooks, mocks…) | `{}` |
| `extraEnv`, `envFrom` | More environment for the container | `[]` |
| `cors.origins` | Allowed CORS origins | `*` |
| `supportedEvents` | Enabled event types (comma-separated) | all |
| `ui.defaultLimit`, `ui.maxLimit`, `ui.defaultWindow` | Event list limits | server defaults |
| `sentry.sourceFetch` | Fetch JS sources for stack frames: `private`, `any`, `off` | `private` |
| `update.checkEnabled`, `update.checkInterval` | New-version notice | on, `12h` |
| `update.selfUpdate` | Update from the UI: `auto`, `on`, `off`. In Kubernetes `auto` shows the `helm upgrade` command | `auto` |
| `xdebug.enabled` | Xdebug proxy on port 9003 | `false` |
| `xdebug.ideAddr`, `xdebug.mode`, `xdebug.idleTimeout`, `xdebug.allowEval`, `xdebug.allowControl`, `xdebug.pauseOnFirstLine` | Xdebug proxy settings | server defaults |
| `xdebugTrace.maxUpload`, `xdebugTrace.maxSize`, `xdebugTrace.keep` | Uploaded Xdebug traces | `100MB`, `256MB`, `20` |
| `auth.enabled` | SSO | `false` |
| `auth.provider` | `auth0`, `google`, `github`, `keycloak`, `gitlab`, `oidc` | `oidc` |
| `auth.providerUrl`, `auth.clientId`, `auth.clientSecret`, `auth.callbackUrl`, `auth.scopes` | SSO settings | |
| `auth.jwtSecret` | Session signing key | generated once, kept |
| `auth.existingSecret` | Secret with `client-id`, `client-secret`, `jwt-secret` | `""` |
| `mcp.enabled`, `mcp.transport`, `mcp.addr`, `mcp.authToken` | MCP server for AI assistants | off |
| `mcp.existingSecret`, `mcp.existingSecretKey` | Take the MCP token from a secret | `""`, `mcp-auth-token` |
| `metrics.enabled` | Prometheus `/metrics` (no auth: on the main port it is public through the Ingress; set `metrics.addr` to keep it off the UI port) | `false` |
| `metrics.addr` | Separate metrics address (e.g. `:9090`); empty = main port | `""` |
| `metrics.serviceMonitor.enabled` | Prometheus Operator ServiceMonitor | `false` |
| `service.type` | Service type | `ClusterIP` |
| `service.httpPort`, `smtpPort`, `varDumperPort`, `monologPort`, `proxyPort`, `xdebugPort` | Service ports | `8000`, `1025`, `9912`, `9913`, `8080`, `9003` |
| `service.annotations` | Service annotations | `{}` |
| `tcpService.enabled`, `type`, `annotations`, `extraSpec` | Second Service for the TCP ports | off, `LoadBalancer` |
| `ingress.*` | Ingress for the web UI | off |
| `podSecurityContext`, `securityContext` | Non-root, read-only root filesystem (see Security) | set |
| `resources` | Requests 50m CPU, 128Mi memory; no limits | |
| `nodeSelector`, `tolerations`, `affinity` | Scheduling | empty |

See [`values.yaml`](values.yaml) for every option.

## Uninstall

```bash
helm uninstall buggregator
```

The PVC is deleted with the release. Back up `/data/buggregator.db` first if you need it.

## Releases

A tag `vX.Y.Z` equal to `version` in `Chart.yaml` publishes `oci://ghcr.io/buggregator/helm-chart/buggregator:X.Y.Z` and a GitHub release with the packaged chart.
