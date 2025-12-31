#!/bin/bash
set -euo pipefail

NAMESPACE="smart-home"
TIMEOUT=180
SKIP_MINIKUBE_START=0
DO_DELETE=0
WIPE_DATA=0

# ANSI colors
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
RESET='\033[0m'

# Parse flags
while [[ $# -gt 0 ]]; do
  case $1 in
    -s|--skip)
      SKIP_MINIKUBE_START=1
      shift
      ;;
    -w|--wipe-data)
      WIPE_DATA=1
      shift
      ;;
    -d|--delete)
      DO_DELETE=1
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [[ "$DO_DELETE" -eq 1 ]]; then
  if [[ "$WIPE_DATA" -eq 1 ]]; then
    echo -e "${YELLOW}Deleting Minikube cluster (wipe data)...${RESET}"
    minikube delete || true
    exit 0
  else
    echo -e "${YELLOW}Deleting workloads in namespace (keeping PVC data)...${RESET}"
    kubectl delete ns "$NAMESPACE" --ignore-not-found=true
    exit 0
  fi
fi

if [[ "$SKIP_MINIKUBE_START" -eq 0 ]]; then
  echo -e "${CYAN}Starting Minikube...${RESET}"
  minikube start --driver=docker --memory=3072 --cpus=2
else
  echo -e "${CYAN}Skipping Minikube start as requested.${RESET}"
fi

echo -e "${CYAN}Enabling addons...${RESET}"
minikube addons enable ingress
minikube addons enable metrics-server

# Start tunnel (needed only for Services of type LoadBalancer)
# If your dashboard-svc is LoadBalancer, keep this.
echo -e "${CYAN}Starting minikube tunnel (for LoadBalancer services)...${RESET}"
nohup minikube tunnel > minikube-tunnel.log 2>&1 &

echo -e "${CYAN}Applying namespace...${RESET}"
kubectl apply -f 00-namespace.yaml

echo -e "${CYAN}Applying core services (MQTT, Mongo, Backend)...${RESET}"
kubectl -n "$NAMESPACE" apply -f 01-mqtt-manifest.yaml
kubectl -n "$NAMESPACE" rollout status deploy/mqtt-broker-deploy --timeout="${TIMEOUT}s"

kubectl -n "$NAMESPACE" apply -f 03-mongo-manifest.yaml
kubectl -n "$NAMESPACE" rollout status deploy/mongo --timeout="${TIMEOUT}s"

kubectl -n "$NAMESPACE" apply -f 04-backend-cm.yaml
kubectl -n "$NAMESPACE" apply -f 05-backend-manifest.yaml
kubectl -n "$NAMESPACE" rollout status deploy/backend-deploy --timeout="${TIMEOUT}s"

echo -e "${CYAN}Seeding devices if none exist...${RESET}"

IDS=$(
  kubectl -n "$NAMESPACE" run tmp-curl --rm -i \
    --image=curlimages/curl:8.14.1 --restart=Never \
    --command -- sh -lc 'curl -fsS http://backend-svc:5200/api/ids' \
  | grep -Eo '^\[.*\]' | head -n 1
)

if [[ "$IDS" == "[]" ]]; then
  echo -e "${YELLOW}No devices found. Seeding a default door lock...${RESET}"
  kubectl -n "$NAMESPACE" run tmp-seed --rm -i \
    --image=curlimages/curl:8.14.1 --restart=Never \
    --command -- sh -lc 'curl -fsS -X POST http://backend-svc:5200/api/devices \
      -H "Content-Type: application/json" \
      -d "{\"id\":\"1\",\"name\":\"Front Door\",\"room\":\"Entrance\",\"type\":\"door_lock\",\"status\":\"unlocked\",\"parameters\":{\"auto_lock_enabled\":false}}"' \
    >/dev/null
  echo -e "${GREEN}Seed done.${RESET}"
else
  echo -e "${GREEN}Devices already exist: $IDS. Skipping seed.${RESET}"
fi

echo -e "${CYAN}Applying app components (simulator, dashboard svc+deploy)...${RESET}"
kubectl -n "$NAMESPACE" apply -f 02-dashboard-svc.yaml
kubectl -n "$NAMESPACE" apply -f 06-simulator-deployment.yaml
kubectl -n "$NAMESPACE" apply -f 07-dashboard-deployment.yaml

kubectl -n "$NAMESPACE" rollout status deploy/simulator-deploy --timeout="${TIMEOUT}s"
kubectl -n "$NAMESPACE" rollout status deploy/dashboard-deploy --timeout="${TIMEOUT}s"

echo -e "${CYAN}Applying monitoring (node-exporter, kube-state-metrics, prometheus, grafana)...${RESET}"
kubectl -n "$NAMESPACE" apply -f 11-node-exporter-manifest.yaml
kubectl -n "$NAMESPACE" rollout status ds/node-exporter --timeout="${TIMEOUT}s"

kubectl -n "$NAMESPACE" apply -f 12-kube-state-metrics.yaml
kubectl -n "$NAMESPACE" rollout status deploy/kube-state-metrics --timeout="${TIMEOUT}s"

kubectl -n "$NAMESPACE" apply -f 08-prometheus-cm.yaml
kubectl -n "$NAMESPACE" apply -f 09-prometheus-manifest.yml
kubectl -n "$NAMESPACE" rollout status deploy/prometheus --timeout="${TIMEOUT}s"

kubectl -n "$NAMESPACE" apply -f 10-grafana-manifest.yaml
kubectl -n "$NAMESPACE" rollout status deploy/grafana --timeout="${TIMEOUT}s"

echo -e "${GREEN}All core components applied. Current pod status:${RESET}"
kubectl -n "$NAMESPACE" get pods -o wide

echo -e "${CYAN}Dashboard access:${RESET}"
# If dashboard-svc is LoadBalancer and tunnel is running, this may work:
EXTERNAL_IP=$(kubectl -n "$NAMESPACE" get svc dashboard-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [[ -n "${EXTERNAL_IP:-}" ]]; then
  echo -e "${GREEN}dashboard-svc LoadBalancer IP: ${EXTERNAL_IP}${RESET}"
else
  echo -e "${YELLOW}No LoadBalancer IP yet. Opening dashboard service via minikube...${RESET}"
  minikube service -n "$NAMESPACE" dashboard-svc
fi

echo -e "${CYAN}Grafana access:${RESET}"
echo -e "${YELLOW}Run: minikube service -n ${NAMESPACE} grafana-svc --url${RESET}"

echo -e "\n${GREEN}*** Done! ***${RESET}\n"