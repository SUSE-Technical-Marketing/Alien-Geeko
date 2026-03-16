# 🦎 GEEKO // ALIEN TERMINAL

<p align="center">
  <img src="resources/alien-geeko-nostromo.jpg" alt="Geeko" width="600"/>
</p>

> A Nostromo-style CRT terminal web app that displays live Kubernetes cluster vitals,
> featuring SUSE's mascot Geeko as an alien entity haunting your edge nodes.
> Designed for the SUSE Edge KubeCon booth demo — runs on k3s and RKE2,
> deploys via Fleet across mixed x86 and ARM clusters.

---

## What It Does

`alien-geeko` is a single-pod Node.js application that renders a retro
terminal UI in the browser. It queries the Kubernetes API directly at runtime
to surface live cluster information — no init containers, no ConfigMap patching,
no external dependencies beyond the service account token that Kubernetes mounts
automatically.

### Data Sources

| Field | Source |
|---|---|
| K8s version | `GET /version` via K8s API |
| Distribution | Detected from `gitVersion` (`+k3s1` / `+rke2r1` suffix) |
| Node count | `GET /api/v1/nodes` via K8s API |
| Node architecture | Node status `.nodeInfo.architecture` |
| Node role | Node labels (`control-plane`, `etcd`, `worker`) |
| OS image | Node status `.nodeInfo.osImage` |
| Pod IP / Host IP | Downward API (`status.podIP`, `status.hostIP`) |
| Pod / Node name | Downward API (`metadata.name`, `spec.nodeName`) |
| Cluster name | ConfigMap `alien-geeko-config` (set per-cluster via Fleet overlay) |
| Memory used / total | Node.js `os` module (live, pod-level) |
| CPU count / model | Node.js `os` module |
| Load average | Node.js `os` module |
| Uptime | Node.js `os` module |

API results are cached for **60 seconds** to avoid hammering the API server on
resource-constrained edge nodes.

---

## Repository Layout

```
alien-geeko/
├── Dockerfile                       # Multi-arch BCI Node.js 20 image
├── fleet.yaml                       # Fleet bundle — targeting + overlays
├── README.md                        # This file
├── app/
│   ├── server.js                    # Node.js HTTP server + K8s API client
│   └── index.html                   # Nostromo CRT terminal UI (self-contained)
├── k8s/
│   ├── 00-namespace.yaml            # Namespace with PSA labels (k3s + RKE2)
│   ├── 01-rbac.yaml                 # ServiceAccount + ClusterRole (read nodes)
│   ├── 02-deployment.yaml           # Deployment (no init container)
│   ├── 03-configmap.yaml            # Per-cluster config (CLUSTER_NAME)
│   └── 04-service.yaml              # NodePort :30080 + LoadBalancer option
└── overlays/
    ├── pi-cluster/
    │   └── kustomization.yaml       # ARM Pi — sets CLUSTER_NAME
    └── x86-cluster/
        └── kustomization.yaml       # x86 NUC — sets CLUSTER_NAME
```

---

## Prerequisites

| Tool | Purpose |
|---|---|
| Docker with `buildx` | Multi-arch image build |
| `kubectl` | Manual deploy / verification |
| Rancher + Fleet | GitOps multi-cluster deploy |
| k3s ≥ 1.24 **or** RKE2 ≥ 1.24 | Target cluster runtime |

A container registry accessible from your clusters (GHCR, Docker Hub, or a
private registry embedded via EIB for air-gapped deployments).

---

## Building the Image

The image is based on **SUSE BCI Node.js 20** (`registry.suse.com/bci/nodejs:20`)
— the same trusted, FIPS-ready foundation as SUSE Linux Micro. It publishes
native `linux/amd64` and `linux/arm64` layers so the same tag works on your
x86 NUC and Raspberry Pi 5 without any changes.

### Multi-arch build (recommended)

```bash
# Create a multi-arch builder if you don't have one
docker buildx create --name multi-builder --use

# Build and push both amd64 and arm64 in one command
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/YOUR_ORG/alien-geeko:1.0.1 \
  -t ghcr.io/YOUR_ORG/alien-geeko:latest \
  --push .
```

### Local single-arch build (quick test)

```bash
docker build -t alien-geeko:1.0.1 .
docker run --rm -p 3000:3000 alien-geeko:1.0.1
# Open http://localhost:3000 — runs in standalone mode (no K8s API)
```

> **Note:** Before deploying, update the `image:` field in
> `k8s/02-deployment.yaml` to point to your registry.

## Building the Image

The app is distributed as a multi-arch container image built on
**SUSE BCI Node.js 20** (`registry.suse.com/bci/nodejs:20`), which publishes
native layers for both `linux/amd64` and `linux/arm64`. This means the same
image tag runs natively on your x86 NUC and your Raspberry Pi 5 without
emulation or any changes to the manifests.

The recommended approach for a KubeCon demo is to build each architecture
separately — one on a native x86 machine, one on a native Pi 5 — and then
combine them into a single multi-arch manifest. This avoids QEMU emulation,
which is slow and occasionally produces binaries that behave differently from
a native build.

---

### Step 1 — Build the x86 image (run on an amd64 machine)
```bash
docker build \
  --platform linux/amd64 \
  -t YOUR_REGISTRY/alien-geeko:1.0.1-amd64 \
  --push \
  .
```

This builds and immediately pushes the amd64 layer to your registry. The
`--push` flag is required here because `docker manifest create` (Step 3)
needs both images to already exist in the registry before it can reference them.

---

### Step 2 — Build the ARM image (run on an arm machine)
```bash
docker build \
  --platform linux/arm64 \
  -t YOUR_REGISTRY/alien-geeko:1.0.1-arm64 \
  --push .
```

Run this command directly on a Mac M or in a Raspberry Pi. If you do not have direct shell access
to the Pi, you can use a Docker remote context to build on it from your
laptop — see the note below.

---

### Step 3 — Combine both layers into a single multi-arch manifest

Once both architecture-specific images are in the registry, create a combined
manifest that points to both. When Kubernetes pulls `alien-geeko:1.0.1` it
will automatically receive the correct layer for the node's architecture —
the x86 NUC gets the amd64 layer, the Pi 5 gets the arm64 layer, from the
exact same image reference in your deployment manifest.

```bash
docker manifest create YOUR_REGISTRY/alien-geeko:1.0.1 \
  YOUR_REGISTRY/alien-geeko:1.0.1-amd64 \
  YOUR_REGISTRY/alien-geeko:1.0.1-arm64

docker manifest push YOUR_REGISTRY/alien-geeko:1.0.1
```

---

### Step 4 — Also tag as `latest`

Tag the same combined manifest as `latest` so Fleet and any tooling that
does not pin a specific version always pulls the most recent build:
```bash
docker manifest create YOUR_REGISTRY/alien-geeko:latest \
  YOUR_REGISTRY/alien-geeko:1.0.1-amd64 \
  YOUR_REGISTRY/alien-geeko:1.0.1-arm64

docker manifest push YOUR_REGISTRY/alien-geeko:latest
```

---

### Using a remote Docker context

If you prefer to trigger both builds from your laptop without SSH-ing into
the Pi, add the Pi as a remote Docker context:

```bash
# Add the Pi as a named Docker context (run once on your laptop)
docker context create pi \
  --docker "host=ssh://pi@<PI_IP_ADDRESS>"

# Verify the connection
docker context ls

# Build the ARM image using the Pi context
docker --context pi build \
  --platform linux/arm64 \
  -t YOUR_REGISTRY/alien-geeko:1.0.1-arm64 \
  --push \
  .

# Switch back to your local context for the manifest step
docker context use default
```

This keeps your workflow entirely on your laptop while still producing a
native ARM binary with no emulation involved.

---

## Deploying Manually (single cluster)

Use this for local testing on Rancher Desktop or a single k3s / RKE2 node.

```bash
# 1. Apply all manifests in order
kubectl apply -f k8s/

# 2. Verify the pod is Running
kubectl -n alien-geeko get pods -w

# 3. Check the service
kubectl -n alien-geeko get svc

# 4. Access the terminal
#    Option A — port-forward (Rancher Desktop / no external IP)
kubectl port-forward svc/alien-geeko 8080:80 -n alien-geeko
# → http://localhost:8080

#    Option B — NodePort (external k3s / RKE2 node)
kubectl get nodes -o wide   # get INTERNAL-IP
# → http://<NODE_IP>:30080
```

### Verify the K8s API connection

```bash
# Check the pod logs to confirm in-cluster API access
kubectl logs -n alien-geeko \
  $(kubectl get pod -n alien-geeko -l app=alien-geeko -o name)

# Expected output:
# [alien-geeko] Listening on :3000
# [alien-geeko] Node: <node-name> | Arch: arm64
# [alien-geeko] Mode: in-cluster (10.43.0.1:443)
```

### Tear down

```bash
kubectl delete namespace alien-geeko
```

---

## Deploying via Fleet (multi-cluster, recommended)

Fleet is the GitOps engine built into Rancher. It reads `fleet.yaml` from your
Git repository and deploys to all matching clusters automatically, applying the
correct per-cluster overlay for `CLUSTER_NAME`.

### Step 1 — Push your code to Git

```bash
git init && git add . && git commit -m "feat: alien-geeko"
git remote add origin https://github.com/YOUR_ORG/alien-geeko
git push -u origin main
```

### Step 2 — Label your clusters in Rancher

In **Rancher UI → Cluster Management** select each cluster, go to
**⋮ → Edit Config → Labels**, and add:

```yaml
# All demo clusters (required by fleet.yaml default target)
demo: "true"

# ARM clusters
edge-type: pi-cluster

# x86 clusters
edge-type: x86-cluster
```

Fleet uses these labels to decide which bundle to apply to which cluster and
which kustomize overlay to merge in.

### Step 3 — Create a GitRepo in Fleet

In **Rancher UI → Continuous Delivery → Git Repos → Add Repository**:

| Field | Value |
|---|---|
| Name | `alien-geeko` |
| Repository URL | `https://github.com/YOUR_ORG/alien-geeko` |
| Branch | `main` |
| Paths | `/` |
| Target clusters | All clusters with label `demo=true` |

Fleet will immediately begin reconciling. Status turns **Active** once all
target clusters report the bundle as deployed.

### Step 4 — Customize cluster names (optional)

Edit the kustomize overlays to give each cluster a meaningful display name
on the Geeko terminal:

```yaml
# overlays/pi-cluster/kustomization.yaml
patches:
  - patch: |-
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: alien-geeko-config
        namespace: alien-geeko
      data:
        CLUSTER_NAME: "PI-CLUSTER-MADRID-01"   # ← your label here
```

```yaml
# overlays/x86-cluster/kustomization.yaml
patches:
  - patch: |-
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: alien-geeko-config
        namespace: alien-geeko
      data:
        CLUSTER_NAME: "X86-FACTORY-FLOOR-003"  # ← your label here
```

Commit and push — Fleet picks up the change within seconds and reconciles
all targeted clusters automatically.

### How Fleet targeting works

```
fleet.yaml
│
├── target: all-demo-clusters         → label: demo=true
│                                       deploys base k8s/ manifests
│
├── target: pi-arm-cluster            → labels: edge-type=pi-cluster
│   kustomize: overlays/pi-cluster       patches CLUSTER_NAME for Pi nodes
│
├── target: x86-cluster               → labels: edge-type=x86-cluster
│   kustomize: overlays/x86-cluster      patches CLUSTER_NAME for x86 nodes
│
└── target: default                   → fallback, matches everything else
```

---

## k3s and RKE2 Compatibility

The app is specifically designed and tested for k3s and RKE2. Key
distribution-specific behaviours it handles:

### Projected service account tokens

Both k3s and RKE2 use **projected (bound) service account tokens** that the
kubelet rotates approximately every hour. The server re-reads the token from
disk on every K8s API request — never caching it at startup — to survive
rotation without a pod restart.

### Distribution detection

The K8s `gitVersion` from `/version` encodes the distribution:

| gitVersion | Detected as |
|---|---|
| `v1.29.3+k3s1` | k3s |
| `v1.29.3+rke2r1` | RKE2 |
| `v1.29.3` | Kubernetes |

This is surfaced as `distribution` in the `/api/info` response and displayed
in the terminal UI.

### Pod Security Admission (RKE2)

RKE2 enforces PSA cluster-wide. `00-namespace.yaml` declares:

```yaml
pod-security.kubernetes.io/enforce: baseline    # allows non-root containers
pod-security.kubernetes.io/warn: restricted     # warns if not fully restricted
```

The container's `securityContext` already satisfies the `restricted` profile
(`runAsNonRoot`, `allowPrivilegeEscalation: false`, `seccompProfile: RuntimeDefault`,
`capabilities: drop ALL`).

### Single-node k3s (Rancher Desktop)

On single-node k3s the only node carries the `control-plane` taint. The
deployment tolerates it explicitly so the pod schedules on Rancher Desktop
without any manual configuration.

### API server timeout

Requests to the K8s API are capped at **5 seconds**. This prevents the HTTP
response from hanging on resource-constrained Pi nodes under load.

---

## RBAC

The app requires **read-only** access to two resources:

```yaml
# ClusterRole: alien-geeko-reader
rules:
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list"]
  - nonResourceURLs: ["/version"]
    verbs: ["get"]
```

No write permissions of any kind. No access to secrets, pods, or any other
resource. The service account is scoped to the `alien-geeko` namespace.

---

## API Reference

The server exposes three endpoints:

| Endpoint | Description |
|---|---|
| `GET /` | Serves `index.html` — the Nostromo terminal UI |
| `GET /api/info` | Returns cluster info as JSON (60 s cache) |
| `GET /health` | Liveness / readiness probe — returns `200 OK` |

### `/api/info` response shape

```json
{
  "nodeName":     "rpi5-node-01",
  "podName":      "alien-geeko-7d9f8b-xkp2q",
  "namespace":    "alien-geeko",
  "podIP":        "10.42.1.45",
  "hostIP":       "192.168.1.101",
  "clusterName":  "PI-CLUSTER-MADRID-01",
  "nodeArch":     "arm64",
  "nodeRole":     "control-plane",
  "distribution": "k3s",
  "k8sVersion":   "v1.29.3+k3s1",
  "nodeCount":    "3",
  "osRelease":    "SUSE Linux Micro 6.0",
  "memTotal":     "7.64 GB",
  "memUsed":      "2.31 GB",
  "memPercent":   30,
  "cpuCount":     4,
  "cpuModel":     "Cortex-A76",
  "loadAvg":      "0.42 / 0.38 / 0.31",
  "uptime":       "2d 4h 17m",
  "timestamp":    "2025-03-16T14:32:00.000Z"
}
```

---

## Resource Footprint

Designed for the far edge — runs comfortably on a Raspberry Pi 5 alongside
other demo workloads:

| | Request | Limit |
|---|---|---|
| CPU | 25m | 100m |
| Memory | 32Mi | 64Mi |

---

## Air-gapped Deployment with EIB

To embed this app in an EIB (Edge Image Builder) image for fully air-gapped
k3s deployment, add the container image to your EIB definition:

```yaml
# eib-config.yaml
embeddedArtifacts:
  containerImages:
    - ghcr.io/YOUR_ORG/alien-geeko:1.0.1
```

And place the Kubernetes manifests where k3s auto-applies them on first boot:

```bash
# In your EIB os-files/ directory:
cp -r k8s/ os-files/var/lib/rancher/k3s/server/manifests/alien-geeko/
```

k3s scans `/var/lib/rancher/k3s/server/manifests/` on startup and applies
everything it finds — the app will be running before you even SSH in.

---

## UI Features

- **Live data** — `/api/info` polled every 10 seconds
- **Geeko** — click the alien chameleon to trigger a scream 👾
- **Log stream** — auto-scrolling terminal output with live system messages
- **Vitality bars** — animated signal bars rebuilt every 8 seconds
- **CRT effects** — scanlines, phosphor glow, screen flicker
- **Distribution badge** — shows `k3s` or `RKE2` detected from gitVersion

---

## Troubleshooting

### Pod stuck in `Pending`

```bash
kubectl describe pod -n alien-geeko <pod-name>
```

On single-node k3s (Rancher Desktop) the node may have a `control-plane` taint.
The deployment tolerates it — if the pod is still pending, confirm the taint:

```bash
kubectl get node -o jsonpath='{.items[*].spec.taints}'
```

### Node count / K8s version shows `unknown` / `?`

The app couldn't reach the K8s API. Check RBAC is applied:

```bash
kubectl get clusterrolebinding alien-geeko-reader
kubectl auth can-i list nodes \
  --as=system:serviceaccount:alien-geeko:alien-geeko
# → yes
```

Check the pod logs for the specific error:

```bash
kubectl logs -n alien-geeko -l app=alien-geeko
# Look for: [geeko] /version: ... or [geeko] /api/v1/nodes: ...
```
### Can't access the app on Rancher Desktop

NodePort addresses the VM's internal network, not `localhost`. Use port-forward:

```bash
kubectl port-forward svc/alien-geeko 8080:80 -n alien-geeko
# → http://localhost:8080
```

### Fleet bundle stuck in `Modified` or `OutOfSync`

```bash
# In Rancher UI → Continuous Delivery → Git Repos → alien-geeko → Force Update
# Or via CLI:
kubectl -n fleet-default get bundle
kubectl -n fleet-default describe bundle alien-geeko
```

---

*GEEKO // ALIEN — In space, no one can hear you provision.*
