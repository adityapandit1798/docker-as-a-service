#!/bin/bash

# Ensure Kind is installed
if ! command -v kind &> /dev/null; then
  echo "Kind is not installed. Installing Kind..."
  go install sigs.k8s.io/kind@v0.29.0
fi

# Ensure Docker is running
if ! docker info > /dev/null 2>&1; then
  echo "Docker is not running. Please start Docker."
  exit 1
fi

# Define cluster name
CLUSTER_NAME="multi-tenant-kind-cluster"

# Delete existing cluster if it exists
kind delete cluster --name "$CLUSTER_NAME" || true

# Create Kind cluster
echo "Creating Kind cluster..."
kind create cluster --name "$CLUSTER_NAME"

# Wait for cluster to be ready
kubectl wait --for=condition=Ready node --all --timeout=60s

# Install Calico
echo "Installing Calico CNI..."
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/calico.yaml 

# Wait for Calico to be ready
kubectl wait --namespace kube-system \
  --for=condition=Ready pod \
  --selector k8s-app=calico-node \
  --timeout=60s

# Run tenant provisioning script
echo "Provisioning tenants..."
#./create-tenant.sh tenant-a

echo "✅ Kind cluster setup complete!"
