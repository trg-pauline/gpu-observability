#!/bin/bash
# Complete deployment script for Grafana GPU Dashboard
set -e

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

echo "✅ Grafana is ready!"
echo ""

# Step 2: Create token secret
echo "Step 2/4: Creating Prometheus token secret..."

# Check if secret already exists
if oc get secret grafana-sa-token -n $NAMESPACE &>/dev/null; then
  echo "Secret grafana-sa-token already exists. Deleting and recreating..."
  oc delete secret grafana-sa-token -n $NAMESPACE
fi

TOKEN=$(oc create token prometheus-k8s -n openshift-monitoring --duration=8760h)
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
echo "✅ Deployment Complete!"
echo "=========================================="
echo ""
echo "Access Grafana at:"
ROUTE=$(oc get route grafana-route -n $NAMESPACE -o jsonpath='{.spec.host}')
echo "  https://$ROUTE"
echo ""
echo "Login credentials:"
echo "  Username: admin"
echo "  Password: admin"
echo ""
echo "Dashboard: Dashboards → NVIDIA GPU Utilization"
echo ""
