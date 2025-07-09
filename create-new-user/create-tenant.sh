#!/bin/bash

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <unique_name>"
  exit 1
fi

TENANT_NAME="$1"
NAMESPACE="${TENANT_NAME}"
SA_NAME="${TENANT_NAME}-sa"

# Resource limits
QUOTA_CPU_REQUEST="500m"
QUOTA_CPU_LIMIT="1"
QUOTA_MEM_REQUEST="512Mi"
QUOTA_MEM_LIMIT="1Gi"
QUOTA_PODS="10"

# Folder to store manifests per tenant
mkdir -p "tenants/${TENANT_NAME}"

# Step 1: Create Linux User for Tenant
echo "==> Creating Linux User..."
sudo useradd "${TENANT_NAME}"
sudo mkdir -p "/home/${TENANT_NAME}/tenant-data"
sudo chown -R "${TENANT_NAME}:${TENANT_NAME}" "/home/${TENANT_NAME}/tenant-data"

# Step 2: Create Namespace
cat <<EOF > "tenants/${TENANT_NAME}/namespace.yaml"
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
  labels:
    pod-security.kubernetes.io/enforce: restricted
    tenant: "${NAMESPACE}"
EOF

# Step 3: Create ServiceAccount
cat <<EOF > "tenants/${TENANT_NAME}/serviceaccount.yaml"
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SA_NAME}
  namespace: ${NAMESPACE}
EOF

# Step 4: Create Role
cat <<EOF > "tenants/${TENANT_NAME}/role.yaml"
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${TENANT_NAME}-role
  namespace: ${NAMESPACE}
rules:
- apiGroups: ["", "apps", "networking.k8s.io"]
  resources: ["pods", "services", "deployments", "ingresses", "pvc", "secrets", "configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF

# Step 5: Create RoleBinding
cat <<EOF > "tenants/${TENANT_NAME}/rolebinding.yaml"
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${TENANT_NAME}-binding
  namespace: ${NAMESPACE}
subjects:
- kind: ServiceAccount
  name: ${SA_NAME}
  namespace: ${NAMESPACE}
roleRef:
  kind: Role
  name: ${TENANT_NAME}-role
  apiGroup: rbac.authorization.k8s.io
EOF

# Step 6: Create ResourceQuota
cat <<EOF > "tenants/${TENANT_NAME}/quota.yaml"
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ${TENANT_NAME}-quota
  namespace: ${NAMESPACE}
spec:
  hard:
    requests.cpu: "${QUOTA_CPU_REQUEST}"
    requests.memory: "${QUOTA_MEM_REQUEST}"
    limits.cpu: "${QUOTA_CPU_LIMIT}"
    limits.memory: "${QUOTA_MEM_LIMIT}"
    pods: "${QUOTA_PODS}"
EOF

# Step 7: Create LimitRange
cat <<EOF > "tenants/${TENANT_NAME}/limitrange.yaml"
apiVersion: v1
kind: LimitRange
metadata:
  name: ${TENANT_NAME}-limit-range
  namespace: ${NAMESPACE}
spec:
  limits:
  - type: Container
    max:
      memory: "512Mi"
      cpu: "500m"
    min:
      memory: "64Mi"
      cpu: "100m"
EOF

# Step 8: Create Default Deny NetworkPolicy
cat <<EOF > "tenants/${TENANT_NAME}/networkpolicy-deny-all.yaml"
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress-egress
  namespace: ${NAMESPACE}
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

# Step 9: Create Allow Same-Namespace NetworkPolicy
cat <<EOF > "tenants/${TENANT_NAME}/networkpolicy-allow-same-ns.yaml"
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: ${NAMESPACE}
spec:
  podSelector: {}
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          tenant: "${NAMESPACE}"
      podSelector: {}
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          tenant: "${NAMESPACE}"
      podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

# Step 10: Create PVC Template
cat <<EOF > "tenants/${TENANT_NAME}/pvc.yaml"
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${TENANT_NAME}-pvc
  namespace: ${NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# Step 11: Apply Kubernetes manifests
kubectl apply -f "tenants/${TENANT_NAME}/namespace.yaml"
kubectl apply -f "tenants/${TENANT_NAME}/serviceaccount.yaml"
kubectl apply -f "tenants/${TENANT_NAME}/role.yaml"
kubectl apply -f "tenants/${TENANT_NAME}/rolebinding.yaml"
kubectl apply -f "tenants/${TENANT_NAME}/quota.yaml"
kubectl apply -f "tenants/${TENANT_NAME}/limitrange.yaml"
kubectl apply -f "tenants/${TENANT_NAME}/networkpolicy-deny-all.yaml"
kubectl apply -f "tenants/${TENANT_NAME}/networkpolicy-allow-same-ns.yaml"
kubectl apply -f "tenants/${TENANT_NAME}/pvc.yaml" || true

# Step 12: Create Tenant-Specific Pod Manifest
USER_ID=$(id -u "${TENANT_NAME}")
GID=$(id -g "${TENANT_NAME}")

cat <<EOF > "tenants/${TENANT_NAME}/pod-sample.yaml"
apiVersion: v1
kind: Pod
metadata:
  name: sample-pod
  namespace: ${NAMESPACE}
spec:
  containers:
  - name: nginx
    image: nginx
    command: ["sh", "-c", "sleep 3600"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
      runAsNonRoot: true
      seccompProfile:
        type: RuntimeDefault
  securityContext:
    runAsUser: ${USER_ID}
    runAsGroup: ${GID}
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
EOF

kubectl apply -f "tenants/${TENANT_NAME}/pod-sample.yaml"

echo ""
echo "✅ Tenant '${TENANT_NAME}' created successfully!"
echo "You can now access this namespace using the ServiceAccount:"
echo ""
echo "kubectl --namespace=${NAMESPACE} --token=\$(kubectl -n ${NAMESPACE} get secret \$(kubectl -n ${NAMESPACE} get sa ${SA_NAME} -o jsonpath='{.secrets[0].name}') -o jsonpath='{.data.token}' | base64 -d) get pods"
echo ""
