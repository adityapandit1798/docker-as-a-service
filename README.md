---
Multi-Tenant Container-as-a-Service Using KinD on Docker
---

## Overview

The goal is to provide multiple tenants with isolated container environments running on a single Docker host, without exposing the Docker daemon directly to tenants. Instead, tenants interact with a Kubernetes API (via KinD cluster), ensuring strong security, resource isolation, and operational control.

Key principles:

- **Logical isolation via Kubernetes namespaces per tenant**
- **Role-Based Access Control (RBAC) scoped to namespaces**
- **Network isolation with Calico Network Policies**
- **Resource quotas and limits to avoid noisy neighbors**
- **Persistent storage isolation via PVCs and StorageClasses**
- **Runtime security (future gVisor integration)**
- **Management via Kubernetes API (future web UI integration)**

---

## Step 1: Install and create KinD cluster

KinD (Kubernetes in Docker) allows you to run a Kubernetes cluster with multiple nodes inside Docker containers, ideal for lightweight multi-tenant CaaS POC.

### KinD cluster config file: `kind-config.yaml`

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    image: kindest/node:v1.33.1
  - role: worker
    image: kindest/node:v1.33.1
  - role: worker
    image: kindest/node:v1.33.1
networking:
  disableDefaultCNI: true  # We'll install Calico CNI later

```

### Create cluster:

```bash
kind create cluster --name tenant-cluster --config kind-config.yaml

```

---

## Step 2: Create tenant namespaces

Namespaces logically isolate tenant resources.

```bash
kubectl create namespace tenant-a
kubectl create namespace tenant-b

```

Verify namespaces:

```bash
kubectl get namespaces

```

---

## Step 3: Setup RBAC for tenants

Each tenant should only have access within their namespace.

### tenant-a-role.yaml

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: tenant-a
  name: tenant-a-admin
rules:
  - apiGroups: [""]
    resources: ["pods", "services", "persistentvolumeclaims", "pods/log"]
    verbs: ["get", "list", "watch", "create", "delete", "patch", "update"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch", "create", "delete", "patch", "update"]

```

### tenant-a-rolebinding.yaml

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tenant-a-binding
  namespace: tenant-a
subjects:
  - kind: User
    name: tenant-a-user
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: tenant-a-admin
  apiGroup: rbac.authorization.k8s.io

```

---

### tenant-b-role.yaml

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: tenant-b
  name: tenant-b-admin
rules:
  - apiGroups: [""]
    resources: ["pods", "services", "persistentvolumeclaims", "pods/log"]
    verbs: ["get", "list", "watch", "create", "delete", "patch", "update"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch", "create", "delete", "patch", "update"]

```

### tenant-b-rolebinding.yaml

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tenant-b-binding
  namespace: tenant-b
subjects:
  - kind: User
    name: tenant-b-user
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: tenant-b-admin
  apiGroup: rbac.authorization.k8s.io

```

### Apply RBAC configs:

```bash
kubectl apply -f tenant-a-role.yaml
kubectl apply -f tenant-a-rolebinding.yaml
kubectl apply -f tenant-b-role.yaml
kubectl apply -f tenant-b-rolebinding.yaml

```

---

## Step 4: Install Calico CNI for network isolation

Disable default CNI in KinD config and install Calico for network policies.

## WHY ?

---

### What is CNI?

**CNI** stands for **Container Network Interface**. It is a standard specification and a set of libraries for configuring network interfaces in Linux containers.

In Kubernetes, CNI is responsible for:

- Creating and managing the network interfaces for pods.
- Assigning IP addresses to pods.
- Ensuring pods can communicate within the cluster and outside (if allowed).
- Applying network policies for isolation and security.

There are many CNI plugins available such as **Calico, Flannel, Weave Net, Canal, Cilium**, etc. Each plugin implements networking differently with varying features.

---

### Why Disable Default CNI in KinD Config?

- KinD by default comes with **a built-in basic CNI plugin** (usually a simple network like **kubenet** or a minimal plugin).
- This default CNI might **not support advanced features** such as:
    - Fine-grained network policies
    - IP address management
    - Advanced routing and security
- If you want to **use a more feature-rich CNI like Calico** (which supports NetworkPolicies, network isolation, eBPF, etc.), you need to disable the default one in the KinD config to avoid conflicts.

In KinD config:

```yaml
networking:
  disableDefaultCNI: true

```

---

### Why Install Calico for Network Policies?

- **Calico** is a powerful, widely-used CNI plugin that supports:
    - **Network policies**: It allows you to define rules on how pods communicate with each other and with external networks. This is crucial for multi-tenant isolation.
    - **Fine-grained security**: You can isolate tenant namespaces from each other at the network level.
    - **Flexible routing and IP management**: It supports BGP, IP pools, and more.
    - **Performance and scalability**: Calico uses Linux kernel features or eBPF for efficient packet processing.
- Without Calico (or another advanced CNI), Kubernetes’ native NetworkPolicies might not work or be limited, meaning you **cannot enforce strict network isolation** between tenants, defeating a major goal of a secure multi-tenant CaaS.

---

### Summary

| Concept | Explanation |
| --- | --- |
| **CNI** | Interface to set up pod networking in Kubernetes clusters. |
| **Disable default CNI** | Prevent conflict, so you can install a more advanced CNI. |
| **Install Calico** | Enables network policies and strong multi-tenant isolation. |

---

---

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/calico.yaml

```

Verify Calico pods:

```bash
kubectl get pods -n kube-system | grep calico

```

## Step 5: Create network policies

### Default deny all ingress and egress in each tenant namespace (`deny-all.yaml`):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: tenant-a
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress

```

Duplicate for tenant-b namespace by changing `namespace: tenant-b`.

Explaination:

## Explaination:

Great question! The **“deny all” network policy** is a foundational security practice in Kubernetes networking, especially in multi-tenant environments like your Container-as-a-Service setup.

---

### Why use a **Deny All** Network Policy?

By default, **Kubernetes pods can communicate with each other freely** across namespaces (unless restricted by Network Policies). This means:

- Pods in **tenant-a** could potentially connect to pods in **tenant-b**.
- Any pod can send/receive traffic unless explicitly blocked.

---

### What does the **Deny All** policy do?

- It **blocks all ingress (incoming) traffic** to pods in the namespace.
- It **blocks all egress (outgoing) traffic** from pods in the namespace (if configured).
- It acts as a "default deny" baseline — **no traffic is allowed unless explicitly permitted**.

---

### Why is this useful?

1. **Zero Trust Baseline:**
    
    Start with **no network connectivity allowed**. This is a security best practice called *default deny* or *zero trust networking*.
    
2. **Tenant Isolation:**
    
    Prevents pods in one namespace (tenant) from reaching pods in another **unless you explicitly allow it via other network policies**.
    
3. **Fine-Grained Control:**
    
    You then create specific **allow policies** to permit traffic *only where necessary*, e.g., allowing pods in the same namespace to communicate or allowing ingress from a trusted source.
    
4. **Prevents Lateral Movement:**
    
    If a pod is compromised, the attacker can't easily move laterally to other pods or tenants because network connectivity is blocked by default.
    

---

### Example flow in your case:

- Apply **deny all ingress** policy in namespace `tenant-a`. Now **no pod in tenant-a accepts any incoming connections**.
- Apply an **allow same namespace** policy to let pods in tenant-a talk to each other.
- Since there's no allow policy permitting cross-namespace communication, **tenant-a and tenant-b remain isolated** network-wise.

---

### Summary table

| Scenario | Behavior Without Deny All | Behavior With Deny All Policy |
| --- | --- | --- |
| Pod communication within same ns | Allowed | Blocked unless allowed explicitly |
| Pod communication across ns | Allowed | Blocked unless allowed explicitly |
| Unknown or unexpected traffic | Allowed | Blocked |
| Baseline security | Weak | Strong (Zero Trust) |

---

### TL;DR

**Deny All** is your "secure default" — it stops *everything* and then you open up the minimum traffic you want, protecting tenants from each other and potential network threats.

---

Want me to help you write those default deny and allow policies?

### Allow same-namespace communication (`allow-same-namespace.yaml`):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: tenant-a
spec:
  podSelector: {}
  ingress:
  - from:
    - podSelector: {}
  egress:
  - to:
    - podSelector: {}
  policyTypes:
  - Ingress
  - Egress

```

Repeat for tenant-b similarly.

Apply these policies:

```bash
kubectl apply -f deny-all.yaml
kubectl apply -f allow-same-namespace.yaml

```

---

## Step 6: Setup resource quotas & limits (example)

Create resource quotas per tenant to limit CPU, memory, storage usage.

Example: `tenant-a-quota.yaml`

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: tenant-a-quota
  namespace: tenant-a
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "4"
    limits.memory: 8Gi
    persistentvolumeclaims: "5"
    requests.storage: 10Gi

```

Repeat for tenant-b.

Apply:

```bash
kubectl apply -f tenant-a-quota.yaml

```

---

## Step 7: Setup persistent storage with Rancher Local Path Provisioner

### Install Local Path Provisioner (already installed if you see `standard` storageclass):

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

```

### tenant-a PVC - `tenant-a-pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: tenant-a-data
  namespace: tenant-a
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: standard

```

### tenant-a Pod using PVC - `tenant-a-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pvc
  namespace: tenant-a
spec:
  containers:
  - name: busybox
    image: busybox
    command: ["sh", "-c", "sleep 3600"]
    volumeMounts:
    - mountPath: /data
      name: tenant-data
    resources:
      requests:
        cpu: 250m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
  volumes:
  - name: tenant-data
    persistentVolumeClaim:
      claimName: tenant-a-data

```

---

### tenant-b PVC - `tenant-b-pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: tenant-b-data
  namespace: tenant-b
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: standard

```

### tenant-b Pod - `tenant-b-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pvc
  namespace: tenant-b
spec:
  containers:
  - name: busybox
    image: busybox
    command: ["sh", "-c", "sleep 3600"]
    volumeMounts:
    - mountPath: /data
      name: tenant-data
    resources:
      requests:
        cpu: 250m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
  volumes:
  - name: tenant-data
    persistentVolumeClaim:
      claimName: tenant-b-data

```

---

### Apply PVC and Pod:

```bash
kubectl apply -f tenant-a-pvc.yaml
kubectl apply -f tenant-a-pod.yaml
kubectl apply -f tenant-b-pvc.yaml
kubectl apply -f tenant-b-pod.yaml

```

---

## Step 8: Verify tenant pods and storage

```bash
kubectl get pvc -n tenant-a
kubectl get pod test-pvc -n tenant-a -w

kubectl get pvc -n tenant-b
kubectl get pod test-pvc -n tenant-b -w

```

Exec into pods to test storage:

```bash
kubectl exec -n tenant-a -it test-pvc -- sh
# inside pod
echo "hello tenant-a" > /data/hello.txt
cat /data/hello.txt

kubectl exec -n tenant-b -it test-pvc -- sh
# inside pod
echo "hello tenant-b" > /data/hello.txt
cat /data/hello.txt

```

---

## Summary of key commands

```bash
# Create KinD cluster
kind create cluster --name tenant-cluster --config kind-config.yaml

# Create namespaces
kubectl create namespace tenant-a
kubectl create namespace tenant-b

# Apply RBAC
kubectl apply -f tenant-a-role.yaml
kubectl apply -f tenant-a-rolebinding.yaml
kubectl apply -f tenant-b-role.yaml
kubectl apply -f tenant-b-rolebinding.yaml

# Install Calico
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/calico.yaml

# Apply network policies
kubectl apply -f deny-all.yaml
kubectl apply -f allow-same-namespace.yaml

# Apply resource quotas
kubectl apply -f tenant-a-quota.yaml
kubectl apply -f tenant-b-quota.yaml

# Install Local Path Provisioner (if needed)
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

# Apply PVCs and Pods
kubectl apply -f tenant-a-pvc.yaml
kubectl apply -f tenant-a-pod.yaml
kubectl apply -f tenant-b-pvc.yaml
kubectl apply -f tenant-b-pod.yaml

```

---

# Example usage

## Step 1: Create namespaces (assuming already done)

---

```bash
kubectl create namespace tenant-a
kubectl create namespace tenant-b

```

---

# Step 2: Deploy nginx pods for tenant-a and tenant-b

Create a YAML manifest for tenant-a `nginx` pod (tenant-a-nginx.yaml):

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  namespace: tenant-a
  labels:
    app: nginx
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80

```

Similarly, create tenant-b-nginx.yaml:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  namespace: tenant-b
  labels:
    app: nginx
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80

```

---

# Step 3: Apply both manifests

```bash
kubectl apply -f tenant-a-nginx.yaml
kubectl apply -f tenant-b-nginx.yaml

```

---

# Step 4: Expose nginx pods as services for access

Create a ClusterIP Service per tenant (or NodePort if you want external access):

tenant-a-nginx-service.yaml:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: tenant-a
spec:
  selector:
    app: nginx
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: ClusterIP

```

tenant-b-nginx-service.yaml:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: tenant-b
spec:
  selector:
    app: nginx
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: ClusterIP

```

Apply:

```bash
kubectl apply -f tenant-a-nginx-service.yaml
kubectl apply -f tenant-b-nginx-service.yaml

```

---

# Step 5: Access nginx pods

Since these are `ClusterIP` services, accessible inside the cluster, you can:

- Use `kubectl port-forward` to forward ports to your local machine for testing.

Example:

```bash
kubectl port-forward svc/nginx-service -n tenant-a 8080:80

```

Now open [http://localhost:8080](http://localhost:8080/) in your browser; you should see the default nginx welcome page from tenant-a.

Similarly for tenant-b:

```bash
kubectl port-forward svc/nginx-service -n tenant-b 8081:80

```

Open [http://localhost:8081](http://localhost:8081/) to see tenant-b's nginx page.

---

# Step 6: Verification

You can check pods status:

```bash
kubectl get pods -n tenant-a
kubectl get pods -n tenant-b

```

You should see both nginx pods running.

---

# Explanation

- Both tenants pull the official `nginx` image independently (Docker Hub public registry).
- Pods run isolated inside their own namespaces.
- NetworkPolicies (if applied) will enforce isolation between tenant namespaces.
- Services expose pods internally; port-forward allows local access for testing.
- This proves multi-tenancy with isolated workloads using the same base Docker image.

---
