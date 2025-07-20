param (
    [switch]$skip
)

$NAMESPACE = "smart-home"
$TIMEOUT = 120

if (-not $skip) {
    Write-Host "Starting Minikube..." -ForegroundColor Cyan
    minikube start --driver=docker --memory=3072 --cpus=2

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Minikube failed to start. Exiting." -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "Skipping Minikube start as requested." -ForegroundColor Cyan
}

Write-Host "Enabling ingress addon..." -ForegroundColor Cyan
minikube addons enable ingress

Write-Host "Opening tunnel to ingress controller..." -ForegroundColor Cyan
Start-Process powershell -WindowStyle Hidden -ArgumentList "-NoExit", "-Command", "minikube tunnel *> minikube-tunnel.log"

Write-Host "Applying LoadBalancer and Ingress..." -ForegroundColor Cyan
kubectl apply -f 00-namespace.yaml
kubectl apply -f 02-dashboard-svc.yaml

Write-Host "Waiting for Minikube tunnel to assign LoadBalancer IP..." -ForegroundColor Yellow

Start-Sleep -Seconds 2

$success = $false
for ($i = 0; $i -lt 30; $i++) {
    $services = kubectl get svc --all-namespaces
    if ($services -match "LoadBalancer") {
        Write-Host "Minikube tunnel is active." -ForegroundColor Green
        $success = $true
        break
    }
    Start-Sleep -Seconds 2
}

if (-not $success) {
    Write-Error "Tunnel did not become active. Exiting."
    exit 1
}

Write-Host "Applying MQTT deployment..." -ForegroundColor Cyan
kubectl apply -f 01-mqtt-manifest.yaml

Write-Host "Waiting for MQTT broker pod in '$NAMESPACE' to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 3
$podsReady = kubectl wait --namespace $NAMESPACE --for=condition=available deployment/mqtt-broker-deploy --timeout="${TIMEOUT}s" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Timeout or error waiting for pod to become ready:"
    Write-Output $podsReady
    exit 1
}
else {
    Write-Host "MQTT broker is ready. Proceeding..." -ForegroundColor Green
}

Write-Host "Applying backend Kubernetes manifests in order..." -ForegroundColor Cyan
kubectl apply -f 03-mongo-secrets.yaml
kubectl apply -f 04-backend-cm.yaml
kubectl apply -f 05-backend-manifest.yaml

Write-Host "Waiting for all backend pods in '$NAMESPACE' to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 3
$podsReady = kubectl wait --namespace $NAMESPACE --for=condition=available deployment/backend-deploy --timeout="${TIMEOUT}s" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Timeout or error waiting for pods to become ready:"
    Write-Output $podsReady
    exit 1
}
else {
    Write-Host "All backend pods are ready. Proceeding..." -ForegroundColor Green
}

Write-Host "Applying all manifests in the current directory..." -ForegroundColor Cyan
kubectl apply -f .

Write-Host "Waiting for the rest of the pods in '$NAMESPACE' to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 3
$podsReady = kubectl wait deployment --all --namespace "$NAMESPACE" --for=condition=available --timeout=${TIMEOUT}s 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Timeout or error waiting for pods readiness:"
    Write-Output $podsReady
    exit 1
}
else {
    Write-Host "All pods in '$NAMESPACE' are ready." -ForegroundColor Green
}

$externalIp = kubectl get svc dashboard-svc -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
if ([string]::IsNullOrEmpty($externalIp)) {
    Write-Host "LoadBalancer external IP not assigned yet. Opening service..." -ForegroundColor Yellow
    minikube service -n $NAMESPACE dashboard-svc
}
else {
    Write-Host "External IP: $externalIp" -ForegroundColor Cyan
    Write-Host "`n*** Done! ***`n" -ForegroundColor Green
}
