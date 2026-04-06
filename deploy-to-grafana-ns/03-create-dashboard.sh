#!/bin/bash
set -e

NAMESPACE="grafana"

echo "Creating NVIDIA GPU Utilization dashboard in Grafana..."

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

# Create dashboard
echo "Creating dashboard..."
oc exec -n $NAMESPACE $POD -- curl -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "dashboard": {
      "title": "NVIDIA GPU Utilization",
      "tags": ["gpu", "nvidia"],
      "timezone": "browser",
      "refresh": "10s",
      "panels": [
        {
          "id": 1,
          "title": "GPU Utilization (%)",
          "type": "timeseries",
          "gridPos": {"x": 0, "y": 0, "w": 12, "h": 8},
          "targets": [{
            "expr": "DCGM_FI_DEV_GPU_UTIL",
            "legendFormat": "{{Hostname}} - GPU {{gpu}}",
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
                "showPoints": "never"
              }
            }
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
            "expr": "DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) * 100",
            "legendFormat": "{{Hostname}} - GPU {{gpu}}",
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
                "showPoints": "never"
              }
            }
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
            "expr": "DCGM_FI_DEV_GPU_TEMP",
            "legendFormat": "{{Hostname}} - GPU {{gpu}}",
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
                "showPoints": "never"
              },
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  {"value": null, "color": "green"},
                  {"value": 70, "color": "yellow"},
                  {"value": 85, "color": "red"}
                ]
              }
            }
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
            "expr": "DCGM_FI_DEV_POWER_USAGE",
            "legendFormat": "{{Hostname}} - GPU {{gpu}}",
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
                "showPoints": "never"
              }
            }
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
