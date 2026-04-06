#!/bin/bash
set -e

NAMESPACE="grafana"

echo "Creating Prometheus datasource in Grafana..."

# Get Grafana pod name
POD=$(oc get pod -n $NAMESPACE -l app=grafana -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD" ]; then
  echo "Error: No Grafana pod found. Is Grafana running?"
  exit 1
fi

echo "Found Grafana pod: $POD"

# Get Prometheus token from secret
TOKEN=$(oc get secret grafana-sa-token -n $NAMESPACE -o jsonpath='{.data.token}' | base64 -d)

if [ -z "$TOKEN" ]; then
  echo "Error: Token not found in secret grafana-sa-token"
  echo "Did you run: TOKEN=\$(oc create token prometheus-k8s -n openshift-monitoring --duration=8760h) && echo \$TOKEN | oc create secret generic grafana-sa-token -n $NAMESPACE --from-literal=token=\$TOKEN"
  exit 1
fi

echo "Token retrieved (length: ${#TOKEN})"

# Create datasource via Grafana API
echo "Creating datasource..."
oc exec -n $NAMESPACE $POD -- curl -X POST \
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
  -u admin:admin

echo ""
echo "✅ Datasource created successfully!"
echo ""
echo "To verify, run:"
echo "  oc exec -n $NAMESPACE $POD -- curl -s http://localhost:3000/api/datasources -u admin:admin"
