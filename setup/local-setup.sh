#!/bin/bash

set -euo pipefail


# Local registry config
REG_NAME='kind-registry'
REG_PORT='5001'
REGISTRY_ADDR="localhost:${REG_PORT}"

# Template for kind cluster config (readable YAML)
KIND_CLUSTER_TEMPLATE='kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerAddress: "0.0.0.0"
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry]
    config_path = "/etc/containerd/certs.d"
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 80
    hostPort: {HOST_PORT_HTTP}
    protocol: TCP
  - containerPort: 443
    hostPort: {HOST_PORT_HTTPS}
    protocol: TCP'
    
function ensure_local_registry() {
  if [ "$(docker inspect -f '{{.State.Running}}' "${REG_NAME}" 2>/dev/null || true)" != 'true' ]; then
    echo "[INFO] Creating local registry container ${REG_NAME} on port ${REG_PORT}..."
    docker run -d --restart=always -p "127.0.0.1:${REG_PORT}:5000" --network bridge --name "${REG_NAME}" registry:2
  else
    echo "[INFO] Local registry ${REG_NAME} already running."
  fi
}

function connect_registry_to_kind_network() {
  if [ "$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "${REG_NAME}")" = 'null' ]; then
    echo "[INFO] Connecting registry to kind network..."
    docker network connect "kind" "${REG_NAME}" || true
  fi
}

function configure_registry_on_nodes() {
  for cluster in "${CLUSTERS[@]}"; do
    for node in $(kind get nodes --name "$cluster"); do
      REGISTRY_DIR="/etc/containerd/certs.d/${REGISTRY_ADDR}"
      echo "[INFO] Configuring registry on node $node for $cluster"
      docker exec "$node" mkdir -p "$REGISTRY_DIR"
      cat <<EOF | docker exec -i "$node" cp /dev/stdin "$REGISTRY_DIR/hosts.toml"
[host."http://${REG_NAME}:5000"]
EOF
    done
  done
}

function preload_nginx_images() {
  # List of images to preload
  images=(
    "registry.k8s.io/ingress-nginx/controller:v1.12.1"
    "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.4.4"
  )
  for img in "${images[@]}"; do
    local_img="${REGISTRY_ADDR}/$(echo $img | cut -d'/' -f2-)"

    # Check if the image exists locally
    if [[ "$(docker images -q "$img" 2> /dev/null)" == "" ]]; then
      echo "[INFO] Pulling $img"
      docker pull "$img"
      echo "[INFO] Tagging $img as $local_img"
      docker tag "$img" "$local_img"
    else
      echo "[INFO] Image $img already exists locally. Skipping pull."
    fi
    echo "[INFO] Pushing $local_img to local registry"
    docker push "$local_img"
  done
}

# Preload agnhost test image to local registry
function preload_agnhost_image() {
  agnhost_img="registry.k8s.io/e2e-test-images/agnhost:2.39"
  local_img="${REGISTRY_ADDR}/e2e-test-images/agnhost:2.39"

  # Check if the image exists locally
  if [[ "$(docker images -q "$agnhost_img" 2> /dev/null)" == "" ]]; then
    echo "[INFO] Pulling $agnhost_img"
    docker pull "$agnhost_img"
    echo "[INFO] Tagging $agnhost_img as $local_img"
    docker tag "$agnhost_img" "$local_img"
  else
    echo "[INFO] Image $agnhost_img already exists locally. Skipping pull."
  fi
  echo "[INFO] Pushing $local_img to local registry"
  docker push "$local_img"
}

function patch_deploy_ingress_yaml() {

  sed -i 's#registry.k8s.io/ingress-nginx/controller:[^"@ ]*[^" ]*#'${REGISTRY_ADDR}'/ingress-nginx/controller:v1.12.1#g' nginx-ingress-controller/deploy-ingress-nginx.yaml
  sed -i 's#registry.k8s.io/ingress-nginx/kube-webhook-certgen:[^"@ ]*[^" ]*#'${REGISTRY_ADDR}'/ingress-nginx/kube-webhook-certgen:v1.4.4#g' nginx-ingress-controller/deploy-ingress-nginx.yaml

}

# Default number of clusters
NUM_CLUSTERS=3

# Parse argument for number of clusters
if [[ $# -ge 1 ]]; then
  if [[ $1 =~ ^[0-9]+$ ]]; then
    NUM_CLUSTERS=$1
  else
    echo "[ERROR] Invalid argument: $1. Please provide a positive integer for the number of clusters."
    exit 1
  fi
fi

# Cluster names and port ranges
CLUSTERS=()
START_HTTP_PORT=8081
START_HTTPS_PORT=8444

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
  for ((i=1; i<=NUM_CLUSTERS; i++)); do
    cluster_name="region-$i"
    CLUSTERS+=("$cluster_name")
    http_port=$((START_HTTP_PORT + i - 1))
    https_port=$((START_HTTPS_PORT + i - 1))
    config_content="${KIND_CLUSTER_TEMPLATE//\{HOST_PORT_HTTP\}/$http_port}"
    config_content="${config_content//\{HOST_PORT_HTTPS\}/$https_port}"
    echo "[INFO] Creating cluster: $cluster_name"
    echo "[DEBUG] Cluster config for $cluster_name:" >&2
    echo "$config_content"
    echo "$config_content" | kind create cluster --name "$cluster_name" --config=-
  done
}

# Set sysctl values inside each kind cluster node container
function set_kind_node_sysctl() {
  for cluster in "${CLUSTERS[@]}"; do
    # Get all docker container IDs for this cluster's nodes
    node_containers=$(docker ps --filter "name=kind_$cluster" --format "{{.ID}}")
    for container in $node_containers; do
      echo "[INFO] Setting sysctl values in container $container for cluster $cluster"
      docker exec -t "$container" bash -c "echo 'fs.inotify.max_user_watches=1048576' >> /etc/sysctl.conf"
      docker exec -t "$container" bash -c "echo 'fs.inotify.max_user_instances=512' >> /etc/sysctl.conf"
      docker exec -i "$container" bash -c "sysctl -p /etc/sysctl.conf"
    done
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
    wait_for_pods_ready "$context" "ingress-nginx"

    echo "[INFO] Deploying service application for $cluster"
    # Alternate between service-a and service-b for demo
  done
}

function argocd_prep_update_kube_config() {
  for kind_cluster in $(kind get clusters ); do
    if [[ "$kind_cluster" == "region-1" ]]; then
      continue
    fi
    controlle_plane_contienr_name=$( docker ps | grep $kind_cluster  | awk '{print $(NF)}' )
    api_server_addr=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$controlle_plane_contienr_name")
    context_name="kind-$kind_cluster"
    kubectl config set-cluster $context_name --server="https://$api_server_addr:6443"
  done

}

argocd_deploy() {
  # Ensure kubectl context points to region-1 (ArgoCD is installed there)
  kubectl config use-context kind-region-1 || true

  echo "[INFO] Deploying ArgoCD..."
  helm upgrade --install argocd argo/argo-cd -n argocd -f argo-cd/argo-cd-values.yaml --create-namespace

  # Wait for ArgoCD pods to be ready
  wait_for_pods_ready "kind-region-1" "argocd"

  # Get the initial admin password
  ARGOCD_PASSWORD=$(kubectl -n argocd --context kind-region-1 get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode)
  echo "[INFO] ArgoCD initial admin password: $ARGOCD_PASSWORD"

  # Non-interactive login to ArgoCD (suppress TLS prompt)
  # Wait for ArgoCD HTTP to become available
  echo "[INFO] Waiting for ArgoCD server to respond on argocd.kind.local:8081"
  for i in {1..30}; do
    if curl -sS --connect-timeout 2 http://argocd.kind.local:8081/healthz >/dev/null 2>&1; then
      echo "[INFO] ArgoCD HTTP endpoint is up"
      break
    fi
    echo -n "."
    sleep 1
  done

  # Ensure any existing CLI session state is cleared to avoid invalid tokens
  ARGODC_SESSION_FILE="$HOME/.argocd/sessions.yaml"
  if [ -f "$ARGODC_SESSION_FILE" ]; then
    echo "[INFO] Removing stale argocd session file"
    rm -f "$ARGODC_SESSION_FILE" || true
  fi

  for i in {1..10}; do
    if yes | argocd login argocd.kind.local:8081 \
        --username admin --password "$ARGOCD_PASSWORD" --insecure --grpc-web; then
      echo "[INFO] Logged into ArgoCD"
      break
    else
      echo "[WARN] ArgoCD login failed, retrying... ($i)"
      sleep 2
    fi
  done

  # Wait a short moment for server to accept the session
  sleep 2

  # Add other clusters to ArgoCD using CLUSTERS array (skip region-1)
  for cluster in "${CLUSTERS[@]}"; do
    if [[ "$cluster" == "region-1" ]]; then
      continue
    fi
    context_name="kind-$cluster"
    echo "[INFO] Adding cluster $context_name to ArgoCD"

    # Retry adding cluster because serviceaccount tokens may not be ready immediately
    for attempt in {1..5}; do
      if argocd cluster add "$context_name" --name "$context_name" --yes --upsert; then
        echo "[INFO] Cluster $context_name added to ArgoCD"
        break
      else
        echo "[WARN] Failed to add $context_name (attempt $attempt), retrying..."
        sleep 2
      fi
    done
  done

  echo "[INFO] Current ArgoCD cluster list:"
  argocd cluster list || true

}

function main() {
  run_nginx_proxy
  ensure_local_registry
  connect_registry_to_kind_network
  preload_nginx_images
  preload_agnhost_image
  delete_existing_clusters
  create_clusters
  set_kind_node_sysctl
  wait_for_nodes_ready
  configure_registry_on_nodes
  patch_deploy_ingress_yaml
  deploy_ingress_and_services
  argocd_prep_update_kube_config
  argocd_deploy
}

function run_nginx_proxy() {
  local image_name="nginx-proxy"
  local container_name="nginx-proxy-local"

  # Build the proxy image if it doesn't exist
  if [[ -z "$(docker images -q ${image_name} 2>/dev/null)" ]]; then
    echo "[INFO] Building ${image_name}..."
    docker build -t ${image_name} ../nginx-proxy/ || docker build -t ${image_name} nginx-proxy/
  else
    echo "[INFO] Image ${image_name} already exists."
  fi

  # If a container with the same name is running, leave it; otherwise remove any stopped one
  if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
    if [[ "$(docker inspect -f '{{.State.Running}}' ${container_name})" == "true" ]]; then
      echo "[INFO] ${container_name} already running."
      return 0
    else
      echo "[INFO] Removing existing container ${container_name}"
      docker rm ${container_name} || true
    fi
  fi

  echo "[INFO] Running ${container_name} in detached mode (host network)..."
  docker run -d --name ${container_name} --net=host ${image_name}
}

main
