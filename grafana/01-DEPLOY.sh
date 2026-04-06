#!/bin/bash
set -e # Exit immediately if any command fails

NAMESPACE="grafana"

echo "=========================================="
echo "Grafana GPU Dashboard Deployment"
echo "Namespace: $NAMESPACE"
echo "=========================================="
echo ""

# ============================================
# Step 1: Deploy Grafana instance
# ============================================
echo "▶️  Step 1/4: Deploying Grafana instance..."
oc apply -f grafana-instance.yaml

echo "⏳ Waiting for Grafana pod to be ready..."
oc wait --for=condition=ready pod -l app=grafana -n $NAMESPACE --timeout=300s
echo "✅ Grafana ready"
echo ""

# ============================================
# Step 2: Create token-carrying secret
# ============================================
echo "▶️  Step 2/4: Creating Prometheus token-carrying secret..."

# Delete secret if it already exists (for re-runs)
if oc get secret grafana-sa-token -n $NAMESPACE &>/dev/null; then
  echo "Secret already exists. Deleting and recreating..."
  oc delete secret grafana-sa-token -n $NAMESPACE
fi

# Create token and store in secret
TOKEN=$(oc create token prometheus-k8s -n openshift-monitoring --duration=24h)
echo $TOKEN | oc create secret generic grafana-sa-token -n $NAMESPACE --from-literal=token=$TOKEN
echo "✅ Token secret created"
echo ""

# ============================================
# Step 3: Create Prometheus datasource
# ============================================
echo "▶️  Step 3/4: Creating Prometheus datasource..."

# Get Grafana pod
POD=$(oc get pod -n $NAMESPACE -l app=grafana -o jsonpath='{.items[0].metadata.name}')
if [ -z "$POD" ]; then
  echo "❌ Error: No Grafana pod found"
  exit 1
fi

# Get token from secret
TOKEN=$(oc get secret grafana-sa-token -n $NAMESPACE -o jsonpath='{.data.token}' | base64 -d)
if [ -z "$TOKEN" ]; then
  echo "❌ Error: Token not found in secret"
  exit 1
fi

# Create datasource via Grafana API
oc exec -n $NAMESPACE $POD -- curl -s -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Prometheus-Direct",
    "type": "prometheus",
    "url": "https://thanos-querier.openshift-monitoring.svc.cluster.local:9091",
    "access": "proxy",
    "isDefault": true,
    "jsonData": {
      "httpHeaderName1": "Authorization",
      "tlsSkipVerify": true,
      "timeInterval": "5s"
    },
    "secureJsonData": {
      "httpHeaderValue1": "Bearer '"$TOKEN"'"
    }
  }' \
  http://localhost:3000/api/datasources \
  -u admin:admin > /dev/null

echo "✅ Prometheus datasource created"
echo ""

# ============================================
# Step 4: Create GPU dashboard
# ============================================
echo "▶️  Step 4/4: Creating GPU dashboard..."

# Get datasource UID
DATASOURCE_UID=$(oc exec -n $NAMESPACE $POD -- curl -s \
  http://localhost:3000/api/datasources/name/Prometheus-Direct -u admin:admin | \
  grep -o '"uid":"[^"]*"' | cut -d'"' -f4)

if [ -z "$DATASOURCE_UID" ]; then
  echo "❌ Error: Datasource not found"
  exit 1
fi

# Discover GPU nodes and assign colors
echo "⏳ Discovering GPU nodes..."
GPU_NODES=$(oc exec -n openshift-monitoring prometheus-k8s-0 -- \
  curl -s 'http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL' | \
  grep -o '"Hostname":"[^"]*"' | cut -d'"' -f4 | sort -u)

if [ -z "$GPU_NODES" ]; then
  echo "Warning: No GPU nodes found. Using default colors."
  COLOR_OVERRIDES=""
else
  echo "Found GPU nodes:"
  for node in $GPU_NODES; do
    echo "  ➤ $node"
  done

  # Assign colors to each node
  COLORS=("orange" "blue" "pink" "green" "yellow" "purple")
  COLOR_OVERRIDES=""
  INDEX=0

  for NODE in $GPU_NODES; do
    COLOR="${COLORS[$INDEX]}"
    SHORT_NODE=$(echo "$NODE" | cut -d'.' -f1)

    if [ -n "$COLOR_OVERRIDES" ]; then
      COLOR_OVERRIDES="$COLOR_OVERRIDES,"
    fi

    COLOR_OVERRIDES="$COLOR_OVERRIDES
              {
                \"matcher\": {\"id\": \"byRegexp\", \"options\": \"/.*$SHORT_NODE.*/\"},
                \"properties\": [{\"id\": \"color\", \"value\": {\"mode\": \"fixed\", \"fixedColor\": \"$COLOR\"}}]
              }"

    INDEX=$((INDEX + 1))
    if [ $INDEX -ge ${#COLORS[@]} ]; then
      INDEX=0
    fi
  done
fi

# Create GPU dashboard
oc exec -n $NAMESPACE $POD -- curl -s -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "dashboard": {
      "title": "GPU Observability",
      "tags": ["GPU"],
      "timezone": "browser",
      "refresh": "5s",
      "time": {
        "from": "now-30m",
        "to": "now"
      },
      "panels": [
        {
          "id": 1,
          "title": "GPU Utilization (%)",
          "type": "timeseries",
          "gridPos": {"x": 0, "y": 0, "w": 12, "h": 8},
          "targets": [{
            "expr": "label_replace(DCGM_FI_DEV_GPU_UTIL, \"short_hostname\", \"$1\", \"Hostname\", \"([^.]+).*\")",
            "legendFormat": "{{short_hostname}} (GPU {{gpu}})",
            "refId": "A",
            "datasource": {"type": "prometheus", "uid": "'"$DATASOURCE_UID"'"}
          }],
          "fieldConfig": {
            "defaults": {
              "unit": "percent",
              "min": 0,
              "max": 100,
              "color": {"mode": "palette-classic"},
              "custom": {
                "drawStyle": "line",
                "lineInterpolation": "linear",
                "fillOpacity": 10,
                "showPoints": "never",
                "lineWidth": 2
              }
            },
            "overrides": ['"$COLOR_OVERRIDES"'
            ]
          },
          "options": {
            "legend": {"displayMode": "list", "placement": "bottom"}
          }
        },
        {
          "id": 2,
          "title": "GPU Memory (%)",
          "type": "timeseries",
          "gridPos": {"x": 12, "y": 0, "w": 12, "h": 8},
          "targets": [{
            "expr": "label_replace(DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) * 100, \"short_hostname\", \"$1\", \"Hostname\", \"([^.]+).*\")",
            "legendFormat": "{{short_hostname}} (GPU {{gpu}})",
            "refId": "A",
            "datasource": {"type": "prometheus", "uid": "'"$DATASOURCE_UID"'"}
          }],
          "fieldConfig": {
            "defaults": {
              "unit": "percent",
              "min": 0,
              "max": 100,
              "color": {"mode": "palette-classic"},
              "custom": {
                "drawStyle": "line",
                "lineInterpolation": "linear",
                "fillOpacity": 10,
                "showPoints": "never",
                "lineWidth": 2
              }
            },
            "overrides": ['"$COLOR_OVERRIDES"'
            ]
          },
          "options": {
            "legend": {"displayMode": "list", "placement": "bottom"}
          }
        },
        {
          "id": 3,
          "title": "GPU Temperature (°C)",
          "type": "timeseries",
          "gridPos": {"x": 0, "y": 8, "w": 12, "h": 8},
          "targets": [{
            "expr": "label_replace(DCGM_FI_DEV_GPU_TEMP, \"short_hostname\", \"$1\", \"Hostname\", \"([^.]+).*\")",
            "legendFormat": "{{short_hostname}} (GPU {{gpu}})",
            "refId": "A",
            "datasource": {"type": "prometheus", "uid": "'"$DATASOURCE_UID"'"}
          }],
          "fieldConfig": {
            "defaults": {
              "unit": "celsius",
              "min": 0,
              "color": {"mode": "palette-classic"},
              "custom": {
                "drawStyle": "line",
                "lineInterpolation": "linear",
                "fillOpacity": 10,
                "showPoints": "never",
                "lineWidth": 2
              },
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  {"value": null, "color": "green"},
                  {"value": 70, "color": "yellow"},
                  {"value": 85, "color": "red"}
                ]
              }
            },
            "overrides": ['"$COLOR_OVERRIDES"'
            ]
          },
          "options": {
            "legend": {"displayMode": "list", "placement": "bottom"}
          }
        },
        {
          "id": 4,
          "title": "GPU Power (W)",
          "type": "timeseries",
          "gridPos": {"x": 12, "y": 8, "w": 12, "h": 8},
          "targets": [{
            "expr": "label_replace(DCGM_FI_DEV_POWER_USAGE, \"short_hostname\", \"$1\", \"Hostname\", \"([^.]+).*\")",
            "legendFormat": "{{short_hostname}} (GPU {{gpu}})",
            "refId": "A",
            "datasource": {"type": "prometheus", "uid": "'"$DATASOURCE_UID"'"}
          }],
          "fieldConfig": {
            "defaults": {
              "unit": "watt",
              "min": 0,
              "color": {"mode": "palette-classic"},
              "custom": {
                "drawStyle": "line",
                "lineInterpolation": "linear",
                "fillOpacity": 10,
                "showPoints": "never",
                "lineWidth": 2
              }
            },
            "overrides": ['"$COLOR_OVERRIDES"'
            ]
          },
          "options": {
            "legend": {"displayMode": "list", "placement": "bottom"}
          }
        }
      ]
    },
    "overwrite": true
  }' \
  http://localhost:3000/api/dashboards/db \
  -u admin:admin > /dev/null

echo "✅ GPU dashboard created"
echo ""

# ============================================
# Deployment complete
# ============================================
echo "=========================================="
echo "✅ Deployment complete!"
echo "=========================================="
echo ""
echo "Access Grafana at:"
ROUTE=$(oc get route grafana-route -n $NAMESPACE -o jsonpath='{.spec.host}')
echo "  https://$ROUTE"
echo ""
echo "To add AI metrics dashboard, run:"
echo "  ./02-ADD.sh"
echo ""
