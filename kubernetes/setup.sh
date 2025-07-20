#!/bin/bash

NAMESPACE="smart-home"
TIMEOUT=120
SKIP_MINIKUBE_START=0

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
    *)
      shift
      ;;
  esac
done

if [ "$SKIP_MINIKUBE_START" -eq 0 ]; then
  echo -e "${CYAN}Starting Minikube...${RESET}"
  minikube start --driver=docker --memory=3072 --cpus=2

  if [ $? -ne 0 ]; then
    echo -e "${RED}Minikube failed to start. Exiting.${RESET}"
    exit 1
  fi
else
  echo -e "${CYAN}Skipping Minikube start as requested.${RESET}"
fi

echo -e "${CYAN}Enabling ingress addon...${RESET}"
minikube addons enable ingress

echo -e "${CYAN}Opening tunnel to ingress controller...${RESET}"
nohup minikube tunnel > minikube-tunnel.log 2>&1 &

echo -e "${CYAN}Applying LoadBalancer and Ingress...${RESET}"
kubectl apply -f 00-namespace.yaml
kubectl apply -f 02-dashboard-svc.yaml

echo -e "${YELLOW}Waiting for Minikube tunnel to assign LoadBalancer IP...${RESET}"
sleep 2
for i in {1..30}; do
  if kubectl get svc --all-namespaces | grep -q 'LoadBalancer'; then
    echo -e "${GREEN}Minikube tunnel is active.${RESET}"
    break
  fi
  sleep 2
done

if ! kubectl get svc --all-namespaces | grep -q 'LoadBalancer'; then
  echo -e "${RED}Tunnel did not become active. Exiting.${RESET}"
  exit 1
fi

echo -e "${CYAN}Applying MQTT deployment...${RESET}"
kubectl apply -f 01-mqtt-manifest.yaml

echo -e "${YELLOW}Waiting for MQTT broker pod in '$NAMESPACE' to be ready...${RESET}"
sleep 3
$podsReady=$(kubectl wait --namespace $NAMESPACE --for=condition=available deployment/mqtt-broker-deploy --timeout="${TIMEOUT}s" 2>&1)

if [ $? -ne 0 ]; then
  echo -e "${RED}Timeout or error waiting for pod to become ready:${RESET}"
  echo "$podsReady"
  exit 1
else
  echo -e "${GREEN}MQTT broker is ready. Proceeding...${RESET}"
fi

echo -e "${CYAN}Applying backend Kubernetes manifests in order...${RESET}"
kubectl apply -f 03-mongo-secrets.yaml
kubectl apply -f 04-backend-cm.yaml
kubectl apply -f 05-backend-manifest.yaml

echo -e "${YELLOW}Waiting for all backend pods in '$NAMESPACE' to be ready...${RESET}"
sleep 3
podsReady=$(kubectl wait --namespace $NAMESPACE --for=condition=available deployment/backend-deploy --timeout="${TIMEOUT}s" 2>&1)

if [ $? -ne 0 ]; then
  echo -e "${RED}Timeout or error waiting for pods to become ready:${RESET}"
  echo "$podsReady"
  exit 1
else
  echo -e "${GREEN}All backend pods are ready. Proceeding...${RESET}"
fi

echo -e "${CYAN}Applying all manifests in the current directory...${RESET}"
kubectl apply -f .

echo -e "${YELLOW}Waiting for the rest of the pods in '$NAMESPACE' to be ready...${RESET}"
sleep 3
podsReady=$(kubectl wait deployment --all --namespace "$NAMESPACE" --for=condition=available --timeout=${TIMEOUT}s 2>&1)

if [ $? -ne 0 ]; then
  echo -e "${RED}Timeout or error waiting for pods readiness:${RESET}"
  echo "$podsReady"
  exit 1
else
  echo -e "${GREEN}All pods in '$NAMESPACE' are ready.${RESET}"
fi

EXTERNAL_IP=$(kubectl get svc dashboard-svc -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -z "$EXTERNAL_IP" ]; then
  echo -e "${YELLOW}LoadBalancer external IP not assigned yet. Opening service...${RESET}"
  minikube service -n $NAMESPACE dashboard-svc
else
  echo -e "${CYAN}External IP: $EXTERNAL_IP${RESET}"
  echo -e "\n${GREEN}*** Done! ***${RESET}\n"
fi
