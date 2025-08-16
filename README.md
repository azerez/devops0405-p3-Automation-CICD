🚀 DevOps Phase 3 — CI/CD with Jenkins, Helm & Kubernetes

This repository (devops0405-p3-Automation-CICD) builds on:
Phase‑1 (Flask + Docker + Docker Hub)
Phase‑2 (Kubernetes on Minikube) 
And adds a Jenkins multibranch CI/CD pipeline, Helm packaging & publishing, and end‑to‑end automation from image build to deployment.


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
│     ├─ values.yaml              # NodePort type; nodePort: 30500; containerPort: 5000
│     └─ templates/
│        ├─ deployment.yaml       # K8s Deployment; image repo:tag injected by Jenkins/Helm
│        └─ service.yaml          # K8s Service (NodePort, fixed external nodePort 30500)
├─ k8s/                           # (manifests from Phase‑2, kept for reference)
├─ Jenkinsfile                    # Multibranch pipeline: build → push → lint → bump → package → publish → deploy
└─ README.md                      # This file


🌐 Stable Port & Access (Minikube)

- The Service is NodePort with a fixed external port 30500 (pinned in helm/flaskapp/values.yaml).
- Access URL example: http://$(minikube ip):30500.
- The container listens on port 5000 inside the pod (Flask default).

🧰 CI/CD — What the Jenkinsfile Does (Stage by Stage)

1. Checkout (Declarative / Checkout)  
   Pulls the project from GitHub (Multibranch discovery). 

2. Build Docker Image 🐳  
   Builds App/Dockerfile and tags:
   - docker.io/erezazu/devops0405-docker-flask-app:<short-commit>
   - docker.io/erezazu/devops0405-docker-flask-app:latest

3. Test 🧪  
   Placeholder for unit tests (currently a no‑op with a clear message).

4. Push Docker Image ⤴️  
   Logs in to Docker Hub using Jenkins credentials ID docker-hub-creds and pushes both tags.

5. Helm Lint ✅  
   helm lint helm/flaskapp to validate chart structure/templates.

6. Helm Version Bump (conditional) 🔖  
   Runs only if files under helm/* changed (or a force flag is set):
   - Auto‑bumps patch in Chart.yaml (e.g., 0.1.1 → 0.1.2) and aligns appVersion.
   - Prints what changed (old → new).

7. Commit Helm Version to Git 📝  
   Commits the bumped Chart.yaml with message  
   ci(helm): bump chart to X.Y.Z [skip ci] and pushes back to main using a GitHub token.

8. Helm Package (conditional) 📦  
   helm package produces helm/dist/flaskapp-<ver>.tgz and archives it in Jenkins.

9. Helm Publish (OCI, conditional) ☸️  
   Logs in to Docker Hub’s registry and pushes the packaged chart to:  
   oci://registry-1.docker.io/erezazu/flaskapp (Helm tags 0.1.x accumulate over time).

10. Deploy to Kubernetes 🚢  
    Uses KUBECONFIG to run:
    bash
    helm upgrade --install flaskapp helm/flaskapp -n dev --create-namespace \
      --set image.repository=docker.io/erezazu/devops0405-docker-flask-app \
      --set image.tag=<short-commit>
    
11. Post Actions 🧾  
    Prints a clear success/failure summary.



🔼 When Does the Chart Version Increase & Get Published?

- Only when files under helm/** changed in the last commit (or when a force path is used).  
- That triggers a patch bump in Chart.yaml and publishes the packaged chart to the OCI Helm repo  
  erezazu/flaskapp on Docker Hub with a new 0.1.x tag.

🖥️ Local Quick Start 

bash
1) Build the app image locally (optional; CI does this automatically)
docker build -f App/Dockerfile -t erezazu/devops0405-docker-flask-app:dev App

2) Deploy via Helm to Minikube (dev namespace); values.yaml pins NodePort 30500
helm upgrade --install flaskapp helm/flaskapp -n dev --create-namespace \
  --set image.repository=docker.io/erezazu/devops0405-docker-flask-app \
  --set image.tag=latest

3) Get Minikube IP and test the app
minikube ip
curl http://$(minikube ip):30500/

✅ Verify

Ready‑to‑use access URL: http://<minikube-ip>:30500  


🔗 References

- Docker Hub (Helm OCI chart) — https://hub.docker.com/repository/docker/erezazu/flaskapp/general  
- Docker Hub (App image) — https://hub.docker.com/repository/docker/erezazu/devops0405-docker-flask-app/general  
- GitHub repo — https://github.com/azerez/devops0405-p3-Automation-CICD.git
