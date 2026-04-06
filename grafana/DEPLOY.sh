#!/bin/bash
# Deployment script for Grafana with GPU dashboard only
set -e # Exit immediately if any command fails

NAMESPACE="grafana"

echo "=========================================="
echo "Grafana GPU Dashboard Deployment"
echo "Namespace: $NAMESPACE"
echo "=========================================="
echo ""

# Step 1: Deploy Grafana instance
echo "Step 1/4: Deploying Grafana instance..."
oc apply -f 01-grafana-instance.yaml

echo "Waiting for Grafana pod to be ready..."
oc wait --for=condition=ready pod -l app=grafana -n $NAMESPACE --timeout=300s

echo "✅ Grafana ready!"
echo ""

# Step 2: Create token-carrying secret
echo "Step 2/4: Creating Prometheus token secret..."

# Delete secret if it already exists
if oc get secret grafana-sa-token -n $NAMESPACE &>/dev/null; then
  echo "Secret grafana-sa-token already exists. Deleting and recreating..."
  oc delete secret grafana-sa-token -n $NAMESPACE
fi

# Store token in secret
TOKEN=$(oc create token prometheus-k8s -n openshift-monitoring --duration=24h)
echo $TOKEN | oc create secret generic grafana-sa-token -n $NAMESPACE --from-literal=token=$TOKEN
echo "✅ Token secret created!"
echo ""

# Step 3: Create datasource
echo "Step 3/4: Creating Prometheus datasource..."
./02-create-datasource.sh
echo ""

# Step 4: Create dashboard
echo "Step 4/4: Creating GPU dashboard..."
./03-create-dashboard.sh
echo ""

echo "=========================================="
echo "✅ Deployment complete!"
echo "=========================================="
echo ""
echo "Access Grafana at:"
ROUTE=$(oc get route grafana-route -n $NAMESPACE -o jsonpath='{.spec.host}')
echo "  https://$ROUTE"
echo ""
echo "To add AI metrics dashboard, run:"
echo "  ./04-create-ai-dashboard.sh"
echo ""
