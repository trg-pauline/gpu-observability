# Observability Dashboards

Monitoring dashboards for OpenShift AI.

## Prerequisites

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

## Deployment Options

### Option 1: OpenShift Console Dashboard

Simple ConfigMap dashboard in OpenShift Console.

**Deploy:**
```bash
oc apply -f dashboard.yaml
```

**Access:**  
OpenShift Console → **Observe** → **Dashboards** → **GPU Observability**

### Option 2: Grafana Instance

Standalone Grafana with GPU + AI metrics dashboards.

**Deploy:**
```bash
cd grafana
./01-DEPLOY.sh  # Deploy Grafana + GPU dashboard
./02-ADD.sh     # Add vLLM AI metrics dashboard
```

**Access:**  
Script outputs the route URL.

**Dashboards:**
1. **GPU Observability** - Utilization, memory, temperature, power
2. **vLLM AI Metrics** - Token throughput, TTFT, request rate
