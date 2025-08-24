🚀 DevOps Phase 3 — CI/CD with Jenkins, Helm & Kubernetes

This repository (devops0405-p3-Automation-CICD) builds on:
Phase-1 (Flask + Docker + Docker Hub)
Phase-2 (Kubernetes on Minikube)
And adds a Jenkins multibranch CI/CD pipeline, Helm packaging & publishing, and end-to-end automation from image build to deployment.


📌 Key Registries & Repos

- Docker Hub — Helm OCI chart: erezazu/flaskapp
  https://hub.docker.com/repository/docker/erezazu/flaskapp/general
- Docker Hub — Application image: erezazu/devops0405-docker-flask-app
  https://hub.docker.com/repository/docker/erezazu/devops0405-docker-flask-app/general
- GitHub repository (this project): devops0405-p3-Automation-CICD
  https://github.com/azerez/devops0405-p3-Automation-CICD.git


📁 Folder Structure

devops0405-p3-Automation-CICD/
├─ App/                           # Flask app + Dockerfile (build context)
├─ helm/
│  └─ flaskapp/
│     ├─ Chart.yaml               # Chart metadata (version, appVersion)
│     ├─ values.yaml              # NodePort; nodePort: 30500; containerPort: 5000
│     └─ templates/
│        ├─ deployment.yaml       # K8s Deployment; image repo:tag via values
│        └─ service.yaml          # K8s Service (NodePort, fixed nodePort 30500)
├─ k8s/                           # (manifests from Phase‑2, kept for reference)
├─ Jenkinsfile                    # Multibranch pipeline stages
└─ README.md                      # This file


🌐 Stable Port & Access (Minikube)

- The Service is NodePort 30500 (pinned in helm/flaskapp/values.yaml).
- Access URL example: http://$(minikube ip):30500.
- The container listens on port 5000 inside the pod (Flask default).


🧰 CI/CD — What the Jenkinsfile Does (Stage by Stage)

1. Checkout (Declarative / SCM)  
   Pull the repository from GitHub (Multibranch discovery).

2. Build Docker Image 🐳  
   Build App/Dockerfile and tag:
   - docker.io/erezazu/devops0405-docker-flask-app:<short-commit>
   - docker.io/erezazu/devops0405-docker-flask-app:latest

3. Push Docker Image ⤴️  
   Log in to Docker Hub using Jenkins credentials ID docker-hub-creds and push both tags.

4. Helm Lint ✅  
   helm lint helm/flaskapp to validate chart structure/templates.

5. Helm Version Bump 🔖  
   Only if files under helm/** changed (or a force path is set):
   - Auto‑bump patch in Chart.yaml (e.g., `0.1.1 → 0.1.2`) and align appVersion.
   - Print what changed (old → new).

6. Commit Helm Version to Git 📝  
   Commit the bumped Chart.yaml with message:  
   `ci(helm): bump chart to X.Y.Z [skip ci] and push back to main using a GitHub token.

7. Helm Package 📦  
   helm package produces helm/dist/flaskapp-<ver>.tgz (archived in Jenkins).

8. Helm Publish-OCI ☸️  
   Log in to the Helm registry and push the packaged chart to:  
   oci://registry-1.docker.io/erezazu/flaskapp (0.1.x tags accumulate).

9. Deploy to Kubernetes 🚢  
   Use KUBECONFIG to upgrade/install the release:
   helm upgrade --install flaskapp helm/flaskapp -n dev --create-namespace --set image.repository=docker.io/erezazu/devops0405-docker-flask-app  --set image.tag=<short-commit>
   
10. TEST 🧪  
    Validate that the image, Helm chart, and deployment are correct and functional.

    Step 1 — Local Image Verification 
    
    docker image inspect <IMAGE:TAG>
   
    ✅ Confirms the image with the current commit tag exists locally.

    Step 2 — Image Run Verification
    
    docker run --rm <IMAGE:TAG> python --version
    
    ✅ Ensures the container runs successfully.

    Step 3 — Registry Image Verification
    
    docker manifest inspect <IMAGE:TAG>
    docker manifest inspect <IMAGE:latest>
  
    ✅ Both the commit tag and latest exist in the remote registry.

    Step 4 — Helm Chart Package Verification  
  
    ls -1 helm/dist/*.tgz
    
    ✅ A packaged Helm chart exists under helm/dist.

    Step 5 — Kubernetes Deployment Verification 
    
    kubectl -n dev rollout status deploy/flaskapp --timeout=90s
    
    ✅ Deployment rollout completed; app is Available.

    Step 6 — In-Cluster Smoke Test
    
    kubectl -n dev run curl-tester --rm -i --restart=Never --image=curlimages/curl:8.8.0 --  -s -o /dev/null -w '%{http_code}'       	http://flaskapp.dev.svc.cluster.local:5000/
   
    ✅ Expect HTTP 200 — service is healthy and reachable inside the cluster.

11. Post Actions 🧾  
    Print a clear success/failure summary.


🔼 When Does the Chart Version Increase & Get Published?

- Only when files under `helm/**` changed in the last commit (or when a force path is used).  
- That triggers a patch bump in `Chart.yaml` and publishes the packaged chart to the OCI Helm repo  
  erezazu/flaskapp** on Docker Hub with a new `0.1.x` tag.


🖥️ Local Quick Start


1) Build the app image locally (optional; CI does this automatically)
docker build -f App/Dockerfile -t erezazu/devops0405-docker-flask-app:dev App

2) Deploy via Helm to Minikube (dev namespace); values.yaml pins NodePort 30500
helm upgrade --install flaskapp helm/flaskapp -n dev --create-namespace   --set image.repository=docker.io/erezazu/devops0405-docker-flask-app   --set image.tag=latest

3) Get Minikube IP and test the app
minikube ip
curl http://$(minikube ip):30500/


✅ Verify — Ready‑to‑use access URL: `http://<minikube-ip>:30500`


🔗 References

- Docker Hub (Helm OCI chart) — https://hub.docker.com/repository/docker/erezazu/flaskapp/general  
- Docker Hub (App image) — https://hub.docker.com/repository/docker/erezazu/devops0405-docker-flask-app/general  
- GitHub repo — https://github.com/azerez/devops0405-p3-Automation-CICD.git
