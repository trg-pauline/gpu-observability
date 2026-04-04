# GPU Observability Dashboard

Simple GPU monitoring dashboard for OpenShift AI.

## Prerequisites

Before using this dashboard, you need:

1. **OpenShift** - OpenShift cluster (4.x or higher)
   ```bash
   oc version
   ```
2. **NVIDIA GPUs** - Physical GPU hardware on your OpenShift nodes
3. **NVIDIA GPU Operator** - Installed and running
   ```bash
   oc get pods -n nvidia-gpu-operator
   ```
4. **DCGM Exporter** - Running on each GPU node (installed by GPU Operator)
   ```bash
   oc get pods -n nvidia-gpu-operator -l app=nvidia-dcgm-exporter
   ```
5. **OpenShift Monitoring** - Prometheus must be collecting metrics
   ```bash
   oc get pods -n openshift-monitoring -l app.kubernetes.io/name=prometheus
   ```

## What It Shows

**4 panels in 2x2 layout:**

- GPU Utilization (%)
- GPU Memory (%)
- GPU Temperature (°C)
- GPU Power (W)

## How to Apply

```bash
oc apply -f dashboard.yaml
```

## How to Access

OpenShift Console → **Observe** → **Dashboards** → **NVIDIA GPU Utilization**

## How It Works

1. **DCGM Exporter** collects GPU metrics from each node
2. **Prometheus** stores the metrics
3. **ConfigMap** with label `console.openshift.io/dashboard: "true"` creates the dashboard
4. **OpenShift Console** displays it

## Edit the Dashboard

```bash
oc edit configmap gpu-utilization-dashboard -n openshift-config-managed
```

Or edit `dashboard.yaml` and reapply.
