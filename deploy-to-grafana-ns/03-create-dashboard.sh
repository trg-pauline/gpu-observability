#!/bin/bash
set -e

NAMESPACE="grafana"

echo "Creating GPU Observability dashboard in Grafana..."

# Get Grafana pod name
POD=$(oc get pod -n $NAMESPACE -l app=grafana -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD" ]; then
  echo "Error: No Grafana pod found. Is Grafana running?"
  exit 1
fi

echo "Found Grafana pod: $POD"

# Get datasource UID
DATASOURCE_UID=$(oc exec -n $NAMESPACE $POD -- curl -s http://localhost:3000/api/datasources/name/Prometheus-Direct -u admin:admin | grep -o '"uid":"[^"]*"' | cut -d'"' -f4)

if [ -z "$DATASOURCE_UID" ]; then
  echo "Error: Datasource 'Prometheus-Direct' not found"
  echo "Did you run: ./02-create-datasource.sh"
  exit 1
fi

echo "Found datasource UID: $DATASOURCE_UID"

# Dynamically get GPU node hostnames from Prometheus
echo "Discovering GPU nodes..."
GPU_NODES=$(oc exec -n openshift-monitoring prometheus-k8s-0 -- \
  curl -s 'http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL' | \
  grep -o '"Hostname":"[^"]*"' | cut -d'"' -f4 | sort -u)

if [ -z "$GPU_NODES" ]; then
  echo "Warning: No GPU nodes found in Prometheus. Dashboard will use default colors."
  COLOR_OVERRIDES=""
else
  echo "Found GPU nodes:"
  echo "$GPU_NODES"

  # Assign colors to each node (orange, blue, pink, then cycle)
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

# Create dashboard with dynamic color overrides
echo "Creating dashboard with dynamic GPU colors..."
oc exec -n $NAMESPACE $POD -- curl -X POST \
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
  -u admin:admin

echo ""
echo "✅ Dashboard created successfully!"
echo ""
echo "Access your dashboard at:"
ROUTE=$(oc get route grafana-route -n $NAMESPACE -o jsonpath='{.spec.host}')
echo "  https://$ROUTE/dashboards"
echo ""
echo "Login with: admin/admin"
