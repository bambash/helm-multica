# n8s-admin Agent — Design Spec

**Date:** 2026-05-22
**Status:** Approved

## Goal

Deploy a Multica Claude agent named `multica-agent-n8s-admin` in the `multica` namespace that has `kubectl` and `helm` available in its container image and full cluster-admin access via a dedicated ServiceAccount. Update the Kubernetes Administrator agent definition in Multica to include detailed cluster and GitOps context.

---

## Component 1 — `multica-agent-image` Dockerfile

**Repo:** `bambash/multica-agent-image`

Add two layers after the existing tool installs, before `USER agent`:

- **kubectl** — download latest stable binary from `dl.k8s.io`, install to `/usr/local/bin/kubectl`, chmod +x
- **helm** — install via `https://get.helm.sh/get-helm-3.sh` official script

Both tools are installed as root so they land on the system PATH for the `agent` user.

CI (`.github/workflows/build.yaml`) already triggers on push to `main` and publishes `ghcr.io/bambash/multica-agent:latest`. No workflow changes needed.

---

## Component 2 — `helm-multica` chart

**Repo:** `bambash/helm-multica`

### 2a — `agent-statefulset.yaml`

Replace hardcoded `serviceAccountName: claude` with a conditional:

```yaml
serviceAccountName: {{ if $agent.serviceAccount }}{{ $agent.serviceAccount.name }}{{ else }}claude{{ end }}
```

Existing agents that do not define `serviceAccount` in their values continue to use the `claude` SA — no breaking change.

### 2b — New template `agent-rbac.yaml`

Iterates `agents` and conditionally emits Kubernetes RBAC resources:

```
for each agent in agents:
  if agent.serviceAccount.create == true:
    emit ServiceAccount (name: agent.serviceAccount.name, namespace: release namespace)
    if agent.serviceAccount.clusterRoleBinding is set:
      emit ClusterRoleBinding → clusterRole: agent.serviceAccount.clusterRoleBinding.clusterRole
    # no clusterRoleBinding block = no binding emitted
```

ServiceAccount labels follow the standard `multica.labels` helper. ClusterRoleBinding name matches the ServiceAccount name.

### 2c — `values.yaml` schema documentation

Add a commented schema block under `agents:` to document the optional `serviceAccount` fields. No actual `n8s-admin` entry in chart defaults — agent instances belong in application values.

#### Agent `serviceAccount` schema (all fields optional):

```yaml
agents:
  <name>:
    # Optional. If omitted, pods use the 'claude' SA (existing default).
    serviceAccount:
      create: true              # create the SA in this release's namespace
      name: multica-n8s-admin  # SA name; referenced by the StatefulSet
      clusterRoleBinding:       # omit entirely to skip binding
        clusterRole: cluster-admin
```

---

## Component 3 — `gitops-argo` application values

**Repo:** `bambash/gitops-argo`
**File:** `apps/multica/values.yaml`

Add under `agents:`:

```yaml
n8s-admin:
  enabled: true
  type: claude
  replicas: 1
  image:
    repository: ghcr.io/bambash/multica-agent
    tag: latest
    pullPolicy: Always
  serviceAccount:
    create: true
    name: multica-n8s-admin
    clusterRoleBinding:
      clusterRole: cluster-admin
  persistence:
    storageClass: openebs-hostpath
    workspaceSize: 30Gi
    homeSize: 5Gi
```

ArgoCD (`multica-appset.yaml`) watches `bambash/helm-multica` chart + `bambash/gitops-argo` values, syncs automatically on push with `automated.selfHeal: true`.

---

## Component 4 — Multica API: update Kubernetes Administrator agent definition

**Endpoint:** `https://multica.n8s.dev`
**Auth:** PAT from OpenBao at `n8s/multica/daemon` → field `token`

### Steps

1. Set up `bao` auth (out-of-cluster: use `~/.vault-token`)
2. `bao kv get -mount=n8s -field=token multica/daemon` → `$PAT`
3. `GET /api/agents` with `Authorization: Bearer $PAT` → find agent named "Kubernetes Administrator"
4. `PATCH /api/agents/{id}` with updated `instructions` field

### Updated instructions content

The new instructions must include:

**Cluster identity and topology:**
- Cluster type: self-hosted bare-metal kubeadm
- Nodes: `k8s-1` (control-plane, Ubuntu 22.04, 2 vCPU/4GB) + `slab1/2/3` (workers, Rocky Linux 10.0, 16 vCPU/13–15GB)
- API server: `https://192.168.1.130:6443`, context: `kubernetes-admin@kubernetes`
- CNI: Calico v3.27.3 (VXLAN)
- Load balancer: MetalLB v0.14.9, IP pool `192.168.1.225–250`
- Ingress: ingress-nginx at `192.168.1.240`, domain `n8s.dev`
- Storage: OpenEBS hostpath (default), LVM + ZFS CSI drivers — PVCs are node-local
- TLS: cert-manager v1.16.2
- Backup: Velero v1.16.1
- DNS: CoreDNS (in-cluster) + AdGuard Home (`.241`/`.242`)

**Operational constraints (self-hosted):**
- No cloud autoscaler — fixed node capacity
- MetalLB IP pool is finite — LoadBalancer service exhaustion is a real risk
- PVCs are node-local — not portable without data migration
- etcd, kube-apiserver, kube-scheduler are self-operated on `k8s-1`
- Upgrades are manual via `kubeadm upgrade`

**GitOps / ArgoCD setup:**
- GitOps repo: `git@github.com:bambash/gitops-argo.git`
- ArgoCD version: v3.3.4
- Pattern: App of Apps — `bootstrap/home-n8s-dev.yaml` seeds a root Application that watches `clusters/home-n8s-dev/`
- `clusters/home-n8s-dev/apps/` contains ArgoCD Application manifests (or ApplicationSets) per workload
- `clusters/home-n8s-dev/apps/kustomization.yaml` lists all active apps
- Application values live in `apps/<app>/values.yaml` in the same repo; the `multica` ApplicationSet (`multica-appset.yaml`) pulls chart from `bambash/helm-multica` and values from `gitops-argo`
- Sync policy: `automated.prune: true`, `selfHeal: true` — out-of-band changes are reverted
- To deploy a change: push to the relevant repo; ArgoCD reconciles within seconds
- To add a new app: add an Application/ApplicationSet manifest under `clusters/home-n8s-dev/apps/` and register it in `kustomization.yaml`

---

## Sequencing

1. Update `multica-agent-image` Dockerfile → push → wait for CI image build
2. Update `helm-multica` chart (StatefulSet + new RBAC template + values schema)
3. Update `gitops-argo` values (enable n8s-admin agent)
4. ArgoCD auto-syncs → StatefulSet, SA, and CRB created in cluster
5. Call Multica API to update Kubernetes Administrator agent definition

Steps 2 and 3 can be committed in parallel. Step 4 is automatic. Step 5 is independent and can run any time after step 1 is live (PAT access is out-of-cluster).
