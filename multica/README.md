# Multica Helm Chart

Helm chart for deploying [Multica](https://github.com/multica-ai/multica) — the open-source managed agents platform — on Kubernetes.

## Architecture

| Component | Description | Technology |
|-----------|-------------|------------|
| **Backend** | REST API + WebSocket server | Go (single binary) |
| **Frontend** | Web application | Next.js 16 |
| **Database** | Primary data store | PostgreSQL 17 with pgvector |

The chart deploys the backend and frontend from pre-built images published to [GHCR](https://github.com/multica-ai/multica/pkgs/container/multica-backend). The backend runs database migrations automatically on startup via an init container.

Users who run AI agents locally also install the `multica` CLI and run the agent daemon on their own machines. This chart only deploys the server-side components.

## Prerequisites

- Kubernetes 1.27+
- Helm 3.14+
- PersistentVolume provisioner (if using built-in PostgreSQL or upload storage)
- [cert-manager](https://cert-manager.io/) (optional, for automatic TLS)
- [Prometheus Operator](https://prometheus-operator.dev/) (optional, for ServiceMonitor)

Each user/team member also needs:
- Docker (to run agents in isolated containers)
- The `multica` CLI installed on their machine
- At least one AI agent CLI (Claude Code, Codex, Copilot, etc.)

## Quick Start

```bash
# Add the Helm repo (if hosted) or install from local path
helm install multica ./multica \
  --set backend.jwtSecret="$(openssl rand -hex 32)" \
  --set backend.resend.apiKey="re_xxxxxxxxxx" \
  --set ingress.enabled=true \
  --set 'ingress.hosts[0].host=multica.example.com'
```

For local testing without an ingress controller:

```bash
helm install multica ./multica

# Port-forward to access
kubectl port-forward svc/multica-frontend 3000:3000 &
kubectl port-forward svc/multica-backend 8080:8080 &

# Open http://localhost:3000
```

## Configuration

### Required Settings

| Parameter | Description | Example |
|-----------|-------------|---------|
| `backend.jwtSecret` | JWT signing secret. Auto-generated if empty, but set explicitly for stable sessions. | `openssl rand -hex 32` |
| `backend.resend.apiKey` | [Resend](https://resend.com) API key for email authentication. Without it, verification codes are printed to backend logs. | `re_xxxxxxxxxx` |

### Database

**Built-in PostgreSQL (default):**

The chart deploys a single-instance PostgreSQL 17 with pgvector. Not suitable for production — use an external database for production deployments.

```yaml
postgresql:
  enabled: true
  auth:
    database: multica
    username: multica
    password: "changeme"
  persistence:
    size: 10Gi
```

**External PostgreSQL:**

```yaml
postgresql:
  enabled: false

externalDatabase:
  host: "postgres.example.com"
  port: 5432
  database: multica
  username: multica
  password: "secure-password"
  sslmode: require

# Or provide a full DSN:
externalDatabase:
  url: "postgres://user:pass@host:5432/multica?sslmode=require"

# Or reference an existing Secret:
externalDatabase:
  existingSecret: "my-database-secret"
```

Ensure the pgvector extension is available in your PostgreSQL instance:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

### Email (Authentication)

Multica uses email-based magic link authentication via [Resend](https://resend.com):

```yaml
backend:
  resend:
    apiKey: "re_xxxxxxxxxx"
    fromEmail: "noreply@yourdomain.com"
```

If Resend is not configured, generated verification codes are printed to backend logs. You can also set a fixed dev code for private test instances:

```yaml
backend:
  appEnv: development
  devVerificationCode: "888888"
```

> **Warning:** Never set `devVerificationCode` on a publicly reachable instance.

### Google OAuth (Optional)

```yaml
backend:
  googleOAuth:
    clientId: "xxxxxxxxxx.apps.googleusercontent.com"
    clientSecret: "GOCSPX-xxxxxxxxxx"
    redirectUri: "https://app.example.com/auth/callback"
```

### Signup Controls

```yaml
backend:
  allowSignup: true
  allowedEmailDomains: "company.com,partners.org"
  allowedEmails: "admin@example.com"
```

### File Storage (S3/CloudFront)

For file uploads and attachments:

```yaml
backend:
  s3:
    bucket: "multica-uploads"
    region: "us-west-2"
  cloudfront:
    domain: "d123456.cloudfront.net"
    keyPairId: "K1234567890"
    privateKey: |
      -----BEGIN RSA PRIVATE KEY-----
      ...
      -----END RSA PRIVATE KEY-----
```

When S3 is not configured, uploads are stored on a PersistentVolume mounted at `/app/data/uploads`.

### Cookie Domain

```yaml
backend:
  cookieDomain: ".example.com"
```

Leave empty for single-host deployments. Only set when frontend and backend are on different subdomains. Do not use an IP address.

### Metrics

The backend can expose Prometheus metrics on a separate port:

```yaml
backend:
  metricsAddr: "0.0.0.0:9090"
```

Enable a ServiceMonitor for automatic scraping by the Prometheus Operator:

```yaml
metrics:
  serviceMonitor:
    enabled: true
    interval: 30s
```

> **Security:** Bind `metricsAddr` to loopback or use private networking, allowlists, or NetworkPolicy in production. Metrics can reveal internal routes, traffic volume, and runtime health.

### Resource Tuning

```yaml
resources:
  backend:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 2000m
      memory: 1Gi
  frontend:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 1000m
      memory: 512Mi
  postgresql:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 2000m
      memory: 2Gi
```

### Autoscaling

```yaml
autoscaling:
  backend:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 70
```

### Image Version Pinning

```yaml
image:
  backend:
    tag: "v0.2.4"
  frontend:
    tag: "v0.2.4"
```

## Ingress Configuration

### Single Host (Recommended for Most Deployments)

Routes all traffic through the frontend on a single hostname. Next.js rewrites proxy `/api`, `/auth`, and `/uploads` to the backend internally. The `/ws` path is routed directly to the backend for WebSocket support.

```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
  hosts:
    - host: multica.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: multica-tls
      hosts:
        - multica.example.com
```

### Separate Hosts (Frontend + Backend on Different Subdomains)

```yaml
ingress:
  enabled: true
  className: "nginx"
  separateHosts:
    enabled: true
    frontendHost: "app.example.com"
    backendHost: "api.example.com"
  tls:
    - secretName: multica-tls
      hosts:
        - app.example.com
        - api.example.com
```

When using separate hosts, also set:

```yaml
backend:
  allowedOrigins: "https://app.example.com"
  cookieDomain: ".example.com"
```

### Ingress Controller-Specific Notes

**NGINX Ingress:**

The chart automatically adds WebSocket annotations when applicable. Additional annotations you may need:

```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "86400"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "86400"
    nginx.ingress.kubernetes.io/affinity: "cookie"
    nginx.ingress.kubernetes.io/session-cookie-name: "multica-route"
```

**Traefik:**

```yaml
ingress:
  className: "traefik"
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: "default-multica-headers@kubernetescrd"
```

**AWS ALB Ingress Controller:**

```yaml
ingress:
  className: "alb"
  annotations:
    alb.ingress.kubernetes.io/scheme: "internet-facing"
    alb.ingress.kubernetes.io/target-type: "ip"
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/healthcheck-path: "/health"
```

## Health Checks

The backend exposes three health endpoints:

| Endpoint | Purpose | Use For |
|----------|---------|---------|
| `/health` | Basic liveness | Liveness probe |
| `/readyz` | Database + migration check | Readiness probe, external monitoring |
| `/healthz` | Alias for `/readyz` | Operator familiarity |

The chart configures:
- **Backend liveness:** `GET /health`
- **Backend readiness:** `GET /readyz`
- **Frontend liveness/readiness:** `GET /`

## Upgrading

```bash
# Update the Helm repo (if hosted)
helm repo update

# Upgrade the release
helm upgrade multica ./multica \
  --reuse-values \
  --set image.backend.tag=v0.3.0 \
  --set image.frontend.tag=v0.3.0
```

Database migrations run automatically via an init container on each backend pod startup. Migrations are idempotent.

To pin to a specific version and prevent accidental upgrades:

```yaml
image:
  backend:
    tag: "v0.2.4"
  frontend:
    tag: "v0.2.4"
```

## Production Checklist

- [ ] Set a fixed `backend.jwtSecret`
- [ ] Use an external PostgreSQL with pgvector (disable built-in)
- [ ] Configure `backend.resend.apiKey` and `backend.resend.fromEmail` for email auth
- [ ] Set `backend.appEnv: production`
- [ ] Enable TLS on the ingress with cert-manager
- [ ] Set resource limits and requests appropriate for your workload
- [ ] Enable HPA if expecting variable load
- [ ] Configure `backend.allowSignup` and email domain restrictions
- [ ] Set up persistent storage for uploads or configure S3/CloudFront
- [ ] Enable Prometheus metrics and configure monitoring/alerting
- [ ] Set `podDisruptionBudget.enabled: true` with `replicaCount.backend >= 2`
- [ ] Configure `topologySpreadConstraints` for multi-zone resilience
- [ ] Review and tighten `securityContext` settings
- [ ] Use a private registry pull secret via `imagePullSecrets`

## Parameters Reference

See [values.yaml](./values.yaml) for the full list of parameters with descriptions.

Key top-level sections:

| Section | Purpose |
|---------|---------|
| `image` | Container image registry, tag, and pull policy |
| `replicaCount` | Number of replicas for backend and frontend |
| `serviceAccount` | ServiceAccount creation and annotations |
| `service` | Service type, ports, and annotations |
| `ingress` | Ingress configuration (single or separate hosts) |
| `resources` | CPU/memory requests and limits per component |
| `autoscaling` | HPA configuration for the backend |
| `podDisruptionBudget` | PDB for backend and frontend |
| `postgresql` | Built-in PostgreSQL settings |
| `externalDatabase` | External database connection details |
| `backend` | All backend application configuration |
| `frontend` | Frontend origin and WebSocket URL |
| `metrics` | Prometheus ServiceMonitor settings |

## CLI Setup (Post-Deployment)

After deploying the chart, each team member who runs AI agents needs to:

```bash
# Install the CLI
brew install multica-ai/tap/multica

# Configure for your deployment
multica config set server_url https://api.example.com
multica config set app_url https://app.example.com

# Authenticate and start the daemon
multica login
multica daemon start
```

## Troubleshooting

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/instance=multica

# View backend logs
kubectl logs -l app.kubernetes.io/component=backend --tail=100 -f

# View migration logs
kubectl logs -l app.kubernetes.io/component=backend -c migrate

# Check database connectivity
kubectl exec deploy/multica-backend -- ./migrate up

# Check health endpoints
kubectl port-forward svc/multica-backend 8080:8080
curl http://localhost:8080/health
curl http://localhost:8080/readyz
```

## License

This chart is distributed under the same license as Multica. See the [Multica repository](https://github.com/multica-ai/multica) for details.
