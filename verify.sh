#!/usr/bin/env bash
# verify.sh — One-click environment & deployment verification for flaskapp on minikube
# Safe on Windows + Docker driver (doesn't block on `minikube service --url`).
# Usage:
#   chmod +x verify.sh
#   ./verify.sh                  # full checks
#   ./verify.sh --fast           # skip any network calls that may wait
#   ./verify.sh --curl           # also curl the computed URL (if NodePort)
#   ./verify.sh -n dev -r flaskapp -s flaskapp -d flaskapp
set -u

NS="dev"
REL="flaskapp"
SVC="flaskapp"
DEPLOY="flaskapp"
FAST=0
DO_CURL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace) NS="$2"; shift 2;;
    -r|--release)   REL="$2"; shift 2;;
    -s|--service)   SVC="$2"; shift 2;;
    -d|--deploy)    DEPLOY="$2"; shift 2;;
    --fast)         FAST=1; shift;;
    --curl)         DO_CURL=1; shift;;
    *)              shift;;
  esac
done

echo "== Tooling versions =="
# kubectl client (yaml prints nicely on Windows too)
kubectl version --client -o yaml 2>/dev/null || kubectl version --client
# kustomize (optional)
kustomize version 2>/dev/null || echo "kustomize: n/a"
# helm
helm version 2>/dev/null || echo "helm: n/a"
# minikube
minikube version 2>/dev/null || echo "minikube: n/a"
# curl
if command -v curl >/dev/null 2>&1; then curl --version | head -n1; else echo "curl: n/a"; fi

echo -e "\n== Kube context =="
kubectl config current-context 2>/dev/null || echo "unknown"

echo -e "\n== Helm status (${REL} in ${NS}) =="
helm -n "$NS" status "$REL" 2>/dev/null || echo "Helm release '${REL}' not found in namespace '${NS}'"

echo -e "\n== Workloads (deploy/rs/pod) for ${DEPLOY} =="
kubectl -n "$NS" get deploy "$DEPLOY" -o wide 2>/dev/null || true
kubectl -n "$NS" get rs -l app.kubernetes.io/instance="$REL" -o wide 2>/dev/null || true
kubectl -n "$NS" get po -l app.kubernetes.io/instance="$REL" -o wide 2>/dev/null || true

echo -e "\n== Service (${SVC}) details =="
kubectl -n "$NS" get svc "$SVC" -o wide 2>/dev/null || { echo "Service '${SVC}' not found in namespace '${NS}'"; echo "Done."; exit 0; }

# Pull service & container ports safely (no blockers)
TYPE=$(kubectl -n "$NS" get svc "$SVC" -o jsonpath='{.spec.type}' 2>/dev/null || echo "")
SPORT=$(kubectl -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "")
NPORT=$(kubectl -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
CPORT=$(kubectl -n "$NS" get deploy "$DEPLOY" -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}' 2>/dev/null || echo "")

echo -e "\nType: ${TYPE:-?} | service.port: ${SPORT:-?} | nodePort: ${NPORT:--} | containerPort: ${CPORT:-?}"

# Compute stable NodePort URL without `minikube service --url` (which can block).
if [[ "$TYPE" == "NodePort" && -n "${NPORT}" ]]; then
  echo -e "\n== Access URL (stable NodePort) =="
  MINI_IP=""
  # Try to limit waiting for minikube ip if 'timeout' exists
  if command -v timeout >/dev/null 2>&1; then
    MINI_IP=$(timeout 3s minikube ip 2>/dev/null || echo "")
  fi
  if [[ -z "$MINI_IP" ]]; then
    MINI_IP=$(minikube ip 2>/dev/null || echo "")
  fi

  if [[ -n "$MINI_IP" ]]; then
    URL="http://${MINI_IP}:${NPORT}"
    echo "$URL"
    if [[ $FAST -eq 0 && $DO_CURL -eq 1 ]]; then
      echo -e "\n== HTTP check (GET /) =="
      curl -m 4 -sS "$URL" | head -n1 || echo "curl failed"
    fi
  else
    echo "Could not resolve 'minikube ip'. Try:  minikube ip"
  fi

  echo -e "\nTip: 'minikube service -n ${NS} ${SVC} --url' opens a local tunnel and WILL BLOCK the terminal until you Ctrl+C."
fi

echo -e "\nDone."
