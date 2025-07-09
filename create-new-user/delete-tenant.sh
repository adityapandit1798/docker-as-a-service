#!/bin/bash

TENANT_NAME="$1"
NAMESPACE="${TENANT_NAME}"

kubectl delete namespace "${NAMESPACE}" || true
sudo deluser --remove-home "${TENANT_NAME}"
