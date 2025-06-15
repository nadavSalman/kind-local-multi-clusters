#!/bin/bash

set -euo pipefail

KIND_CONF_DIR="kind-clusters-conf"
CLUSTERS=(region-a1 region-b1)

function delete_existing_clusters() {
  echo "[INFO] Deleting existing kind clusters if any..."
  existing_clusters=$(kind get clusters || true)
  for cluster in ${existing_clusters}; do
    echo "[INFO] Deleting cluster: $cluster"
    kind delete cluster --name "$cluster"
  done
}

function create_clusters() {
  echo "[INFO] Creating kind clusters..."
  for cluster in "${CLUSTERS[@]}"; do
    echo "[INFO] Creating cluster: $cluster"
    kind create cluster --name "$cluster" --config "$KIND_CONF_DIR/$cluster.yaml"
  done
}

function wait_for_nodes_ready() {
  echo "[INFO] Waiting for all nodes in each cluster to be ready..."
  for cluster in "${CLUSTERS[@]}"; do
    context="kind-$cluster"
    echo -n "[INFO] Checking nodes in cluster: $cluster "
    local spin='-|/'
    local i=0
    while true; do
      not_ready_nodes=$(kubectl get nodes --context "$context" --no-headers | grep -v " Ready" || true)
      if [ -z "$not_ready_nodes" ]; then
        echo -e "\b✔️"
        break
      else
        printf "\b${spin:i++%${#spin}:1}"
        sleep 0.5
      fi
    done
  done
}

function wait_for_pods_ready() {
  local context="$1"
  local namespace="$2"

  echo -n "[INFO] Waiting for pods in $namespace (context: $context) to be ready "

  local spin='-\|/'
  local i=0

  while true; do
    not_ready_pods=$(kubectl get pods -n "$namespace" --context "$context" --no-headers | grep -v " Running" | grep -v " Completed" || true)
    if [ -z "$not_ready_pods" ]; then
      echo -e "\b✔️"
      break
    fi
    printf "\b${spin:i++%${#spin}:1}"
    sleep 0.5
  done
}

function deploy_ingress_and_services() {
  echo "[INFO] Deploying ingress controllers and services..."
  for cluster in "${CLUSTERS[@]}"; do
    context="kind-$cluster"
    echo "[INFO] Deploying ingress controller for $cluster"
    kubectl apply -f nginx-ingress-controller/deploy-ingress-nginx.yaml --context "$context"

    wait_for_pods_ready "$context" "ingress-nginx"

    echo "[INFO] Deploying service application for $cluster"
    if [[ "$cluster" == "region-a1" ]]; then
      kubectl apply -f k8s-deployment/service-a/deployment.yaml --context "$context"
    elif [[ "$cluster" == "region-b1" ]]; then
      kubectl apply -f k8s-deployment/service-b/deployment.yaml --context "$context"
    fi
  done
}

function main() {
  delete_existing_clusters
  create_clusters
  wait_for_nodes_ready
  deploy_ingress_and_services
  echo "[INFO] Environment setup completed successfully."
}

main
