#!/bin/bash
set -e

NAMESPACE="grafana"

echo "===================================================="
echo "Grafana vLLM AI Metrics Dashboard Deployment"
echo "Namespace: $NAMESPACE"
echo "===================================================="
echo ""

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
  echo "Did you run: ./01-DEPLOY.sh"
  exit 1
fi

echo "Found datasource UID: $DATASOURCE_UID"

# Create dashboard
echo "⏳ Creating dashboard..."
oc exec -n $NAMESPACE $POD -- curl -s -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "dashboard": {
      "title": "vLLM AI Metrics",
      "tags": ["AI", "vLLM"],
      "timezone": "browser",
      "refresh": "5s",
      "time": {
        "from": "now-30m",
        "to": "now"
      },
      "panels": [
        {
          "id": 1,
          "title": "Token Throughput",
          "type": "timeseries",
          "gridPos": {"x": 0, "y": 0, "w": 12, "h": 9},
          "targets": [
            {
              "expr": "rate(vllm:prompt_tokens_total{model_name=\"mistral-small-int4\"}[1m])",
              "legendFormat": "Input",
              "refId": "A",
              "datasource": {"type": "prometheus", "uid": "'"$DATASOURCE_UID"'"}
            },
            {
              "expr": "rate(vllm:generation_tokens_total{model_name=\"mistral-small-int4\"}[1m])",
              "legendFormat": "Output",
              "refId": "B",
              "datasource": {"type": "prometheus", "uid": "'"$DATASOURCE_UID"'"}
            }
          ],
          "fieldConfig": {
            "defaults": {
              "unit": "tps",
              "min": 0,
              "color": {"mode": "palette-classic"},
              "custom": {
                "drawStyle": "line",
                "lineInterpolation": "smooth",
                "lineWidth": 3,
                "fillOpacity": 30,
                "showPoints": "auto",
                "pointSize": 5,
                "axisPlacement": "auto",
                "gradientMode": "opacity"
              }
            },
            "overrides": [
              {
                "matcher": {"id": "byName", "options": "Input"},
                "properties": [
                  {"id": "color", "value": {"mode": "fixed", "fixedColor": "orange"}},
                  {"id": "custom.lineWidth", "value": 3}
                ]
              },
              {
                "matcher": {"id": "byName", "options": "Output"},
                "properties": [
                  {"id": "color", "value": {"mode": "fixed", "fixedColor": "pink"}},
                  {"id": "custom.lineWidth", "value": 3}
                ]
              }
            ]
          },
          "options": {
            "legend": {
              "displayMode": "table",
              "placement": "bottom",
              "showLegend": true,
              "calcs": ["mean", "lastNotNull", "max"]
            },
            "tooltip": {
              "mode": "multi",
              "sort": "desc"
            }
          }
        },
        {
          "id": 2,
          "title": "Time to First Token (TTFT)",
          "type": "timeseries",
          "gridPos": {"x": 12, "y": 0, "w": 12, "h": 9},
          "targets": [
            {
              "expr": "histogram_quantile(0.50, rate(vllm:time_to_first_token_seconds_bucket{model_name=\"mistral-small-int4\"}[1m]))",
              "legendFormat": "P50 (Median)",
              "refId": "A",
              "datasource": {"type": "prometheus", "uid": "'"$DATASOURCE_UID"'"}
            },
            {
              "expr": "histogram_quantile(0.95, rate(vllm:time_to_first_token_seconds_bucket{model_name=\"mistral-small-int4\"}[1m]))",
              "legendFormat": "P95",
              "refId": "B",
              "datasource": {"type": "prometheus", "uid": "'"$DATASOURCE_UID"'"}
            },
            {
              "expr": "histogram_quantile(0.99, rate(vllm:time_to_first_token_seconds_bucket{model_name=\"mistral-small-int4\"}[1m]))",
              "legendFormat": "P99",
              "refId": "C",
              "datasource": {"type": "prometheus", "uid": "'"$DATASOURCE_UID"'"}
            }
          ],
          "fieldConfig": {
            "defaults": {
              "unit": "s",
              "min": 0,
              "color": {"mode": "palette-classic"},
              "custom": {
                "drawStyle": "line",
                "lineInterpolation": "smooth",
                "lineWidth": 3,
                "fillOpacity": 20,
                "showPoints": "auto",
                "pointSize": 5,
                "axisPlacement": "auto",
                "gradientMode": "opacity"
              }
            },
            "overrides": [
              {
                "matcher": {"id": "byName", "options": "P50 (Median)"},
                "properties": [
                  {"id": "color", "value": {"mode": "fixed", "fixedColor": "green"}},
                  {"id": "custom.lineWidth", "value": 3}
                ]
              },
              {
                "matcher": {"id": "byName", "options": "P95"},
                "properties": [
                  {"id": "color", "value": {"mode": "fixed", "fixedColor": "yellow"}},
                  {"id": "custom.lineWidth", "value": 2}
                ]
              },
              {
                "matcher": {"id": "byName", "options": "P99"},
                "properties": [
                  {"id": "color", "value": {"mode": "fixed", "fixedColor": "red"}},
                  {"id": "custom.lineWidth", "value": 2}
                ]
              }
            ]
          },
          "options": {
            "legend": {
              "displayMode": "table",
              "placement": "bottom",
              "showLegend": true,
              "calcs": ["mean", "lastNotNull", "max"]
            },
            "tooltip": {
              "mode": "multi",
              "sort": "none"
            }
          }
        },
        {
          "id": 3,
          "title": "Request Rate",
          "type": "timeseries",
          "gridPos": {"x": 0, "y": 9, "w": 8, "h": 6},
          "targets": [{
            "expr": "sum(rate(vllm:request_success_total{model_name=\"mistral-small-int4\"}[1m]))",
            "legendFormat": "Requests/sec",
            "refId": "A",
            "datasource": {"type": "prometheus", "uid": "'"$DATASOURCE_UID"'"}
          }],
          "fieldConfig": {
            "defaults": {
              "unit": "reqps",
              "min": 0,
              "color": {"mode": "thresholds"},
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  {"value": null, "color": "blue"}
                ]
              },
              "custom": {
                "drawStyle": "line",
                "lineInterpolation": "smooth",
                "lineWidth": 3,
                "fillOpacity": 40,
                "showPoints": "auto",
                "pointSize": 5,
                "gradientMode": "scheme"
              }
            }
          },
          "options": {
            "legend": {
              "displayMode": "list",
              "placement": "bottom",
              "showLegend": true,
              "calcs": ["mean", "lastNotNull"]
            },
            "tooltip": {
              "mode": "single"
            }
          }
        },
        {
          "id": 4,
          "title": "Total Tokens Processed",
          "type": "stat",
          "gridPos": {"x": 8, "y": 9, "w": 8, "h": 6},
          "targets": [{
            "expr": "sum(vllm:prompt_tokens_total{model_name=\"mistral-small-int4\"}) + sum(vllm:generation_tokens_total{model_name=\"mistral-small-int4\"})",
            "legendFormat": "Tokens",
            "refId": "A",
            "datasource": {"type": "prometheus", "uid": "'"$DATASOURCE_UID"'"}
          }],
          "fieldConfig": {
            "defaults": {
              "unit": "short",
              "color": {"mode": "thresholds"},
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  {"value": null, "color": "blue"}
                ]
              },
              "mappings": []
            }
          },
          "options": {
            "graphMode": "area",
            "colorMode": "value",
            "orientation": "auto",
            "textMode": "value_and_name",
            "reduceOptions": {
              "calcs": ["lastNotNull"]
            }
          }
        },
        {
          "id": 5,
          "title": "Total Requests Served",
          "type": "stat",
          "gridPos": {"x": 16, "y": 9, "w": 8, "h": 6},
          "targets": [{
            "expr": "sum(vllm:request_success_total{model_name=\"mistral-small-int4\"})",
            "legendFormat": "Requests",
            "refId": "A",
            "datasource": {"type": "prometheus", "uid": "'"$DATASOURCE_UID"'"}
          }],
          "fieldConfig": {
            "defaults": {
              "unit": "short",
              "color": {"mode": "thresholds"},
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  {"value": null, "color": "blue"}
                ]
              },
              "mappings": []
            }
          },
          "options": {
            "graphMode": "area",
            "colorMode": "value",
            "orientation": "auto",
            "textMode": "value_and_name",
            "reduceOptions": {
              "calcs": ["lastNotNull"]
            }
          }
        }
      ]
    },
    "overwrite": true
  }' \
  http://localhost:3000/api/dashboards/db \
  -u admin:admin > /dev/null

echo "✅ Dashboard created successfully!"
echo ""
echo "Access your dashboard at:"
ROUTE=$(oc get route grafana-route -n $NAMESPACE -o jsonpath='{.spec.host}')
echo "  https://$ROUTE/dashboards"
echo ""
