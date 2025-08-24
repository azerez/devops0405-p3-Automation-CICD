// Jenkinsfile — Declarative pipeline tuned to your credentials IDs
// Uses: docker-hub-creds (username+password or PAT), github-token (Secret text), kubeconfig (Kubeconfig file)

pipeline {
  agent any

  options {
    timestamps()
    skipDefaultCheckout(false)
  }

  parameters {
    booleanParam(name: 'FORCE_HELM_PUBLISH', defaultValue: false, description: 'Force bump/package/publish Helm even if no files under helm/ changed')
  }

  environment {
    DOCKER_IMAGE   = 'docker.io/erezazu/devops0405-docker-flask-app'
    HELM_CHART_DIR = 'helm/flaskapp'
    GIT_USER = 'azerez'
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Build Docker Image') {
      steps {
        script {
          env.GIT_SHORT = sh(returnStdout: true, script: 'git rev-parse --short=7 HEAD').trim()
        }
        echo "Building image: ${DOCKER_IMAGE}:${GIT_SHORT}"
        sh '''
          docker build -f App/Dockerfile -t ${DOCKER_IMAGE}:${GIT_SHORT} App
          docker tag ${DOCKER_IMAGE}:${GIT_SHORT} ${DOCKER_IMAGE}:latest
        '''
      }
    }

    stage('Push Docker Image') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds',
                                          usernameVariable: 'DH_USER',
                                          passwordVariable: 'DH_PASS')]) {
          sh '''
            echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin docker.io
            docker push ${DOCKER_IMAGE}:${GIT_SHORT}
            docker push ${DOCKER_IMAGE}:latest
          '''
        }
      }
    }

    stage('Helm Lint') {
      steps { sh "helm lint ${HELM_CHART_DIR}" }
    }

    stage('Helm Version Bump') {
      steps {
        sh '''
          set -e
          if git diff --name-only HEAD~1..HEAD | grep -E '^helm/' >/dev/null 2>&1 || [ "${FORCE_HELM_PUBLISH}" = "true" ]; then
            CHART_FILE="${HELM_CHART_DIR}/Chart.yaml"
            CURR=$(grep '^version:' "$CHART_FILE" | awk '{print $2}')
            IFS=. read -r MA mi pa <<EOF
$CURR
EOF
            : "${pa:=0}"
            pa=$((pa+1))
            NEW="${MA}.${mi}.${pa}"
            sed -i "s/^version:.*/version: ${NEW}/" "$CHART_FILE"
            if grep -q '^appVersion:' "$CHART_FILE"; then
              sed -i "s/^appVersion:.*/appVersion: ${NEW}/" "$CHART_FILE"
            else
              echo "appVersion: ${NEW}" >> "$CHART_FILE"
            fi
            echo "Helm chart version bumped: ${CURR} -> ${NEW}"
            grep -E '^(version|appVersion):' "$CHART_FILE"
          else
            echo "No changes under helm/ and FORCE_HELM_PUBLISH=false — skipping bump."
          fi
        '''
      }
    }

    stage('Commit Helm Version to Git') {
      steps {
        sh '''
          if git diff --name-only HEAD~1..HEAD | grep -E '^helm/' >/dev/null 2>&1 || [ "${FORCE_HELM_PUBLISH}" = "true" ]; then
            echo "[INFO] Commit Chart.yaml back to main..."
          else
            echo "[INFO] No helm changes — skipping commit."
            exit 0
          fi
        '''
        withCredentials([string(credentialsId: 'github-token', variable: 'GTOKEN')]) {
          sh '''
            set -e
            git config user.email "ci@azerez.local"
            git config user.name  "CI Bot"

            origin="$(git config --get remote.origin.url)"
            # --- Conversion without sed/regex (clear & Groovy-safe) ---
            # git@github.com:user/repo.git -> https://github.com/user/repo.git
            case "$origin" in
              git@github.com:*) origin="${origin/git@github.com:/https://github.com/}";;
            esac
            # Derive repo_path = user/repo (strip protocol/host and .git)
            repo_path="$origin"
            repo_path="${repo_path#https://github.com/}"
            repo_path="${repo_path#http://github.com/}"
            repo_path="${repo_path%.git}"
            # ----------------------------------------------------------

            origin_auth="https://${GIT_USER}:${GTOKEN}@github.com/${repo_path}.git"
            git remote set-url origin "$origin_auth"

            git add ${HELM_CHART_DIR}/Chart.yaml || true
            VER="$(grep '^version:' ${HELM_CHART_DIR}/Chart.yaml | awk '{print $2}')"
            git commit -m "ci(helm): bump chart to ${VER} [skip ci]" || true
            git push origin HEAD:main

            # restore remote
            git remote set-url origin "https://github.com/${repo_path}.git"
          '''
        }
      }
    }

    stage('Helm Package') {
      steps {
        sh '''
          if git diff --name-only HEAD~1..HEAD | grep -E '^helm/' >/dev/null 2>&1 || [ "${FORCE_HELM_PUBLISH}" = "true" ]; then
            mkdir -p helm/dist
            helm package "${HELM_CHART_DIR}" -d helm/dist
            ls -l helm/dist
          else
            echo "[INFO] No helm changes — skipping package."
          fi
        '''
        archiveArtifacts artifacts: 'helm/dist/*.tgz', fingerprint: true, allowEmptyArchive: true
      }
    }

    stage('Helm Publish-OCI') {
      steps {
        sh '''
          if git diff --name-only HEAD~1..HEAD | grep -E '^helm/' >/dev/null 2>&1 || [ "${FORCE_HELM_PUBLISH}" = "true" ]; then
            echo "[INFO] Will publish Helm chart to OCI..."
          else
            echo "[INFO] No helm changes — skipping publish."
            exit 0
          fi
        '''
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds',
                                          usernameVariable: 'DH_USER',
                                          passwordVariable: 'DH_PASS')]) {
          sh '''
            helm registry login -u "$DH_USER" -p "$DH_PASS" registry-1.docker.io
            CHART_TGZ="$(ls -t helm/dist/*.tgz | head -n1)"
            echo "[INFO] Pushing chart: $CHART_TGZ"
            helm push "$CHART_TGZ" oci://registry-1.docker.io/${DH_USER}
          '''
        }
      }
    }

    stage('Deploy to Kubernetes') {
      when { branch 'main' }
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KCFG')]) {
          sh '''
            export KUBECONFIG="$KCFG"
            helm upgrade --install flaskapp "${HELM_CHART_DIR}" \
              --namespace dev --create-namespace \
              --set image.repository=${DOCKER_IMAGE} \
              --set image.tag=${GIT_SHORT}
          '''
        }
      }
    }

    stage('TEST') {
      steps {
        sh '''
          set -e
          echo "[INFO] Verify Image Built (local)"
          docker image inspect ${DOCKER_IMAGE}:${GIT_SHORT} >/dev/null 2>&1 || { echo "[ERROR] Image not found"; exit 1; }
          echo "[OK]   Local image exists"

          echo "[INFO] Verify Image Runs"
          docker run --rm ${DOCKER_IMAGE}:${GIT_SHORT} python --version >/dev/null 2>&1 || { echo "[ERROR] Image failed to run"; exit 1; }
          echo "[OK]   Image runs"

          echo "[INFO] Verify Image In Registry"
          docker manifest inspect ${DOCKER_IMAGE}:${GIT_SHORT} >/dev/null || { echo "[ERROR] Remote image not found"; exit 1; }
          docker manifest inspect ${DOCKER_IMAGE}:latest >/dev/null || { echo "[ERROR] Latest tag not found"; exit 1; }
          echo "[OK]   Remote image exists"

          echo "[INFO] Verify Chart Package"
          if ls -1 helm/dist/*.tgz >/dev/null 2>&1; then
            echo "[OK]   Chart package exists"
          else
            echo "[INFO] No chart package found (probably skipped due to no helm changes)"
          fi

          if [ "${BRANCH_NAME}" = "main" ]; then
            echo "[INFO] Verify Rollout"
            kubectl -n dev rollout status deploy/flaskapp --timeout=90s
            echo "[OK]   Deployment rollout completed"

            echo "[INFO] In-Cluster Smoke Test"
            SVC=$(kubectl -n dev get svc -l app.kubernetes.io/instance=flaskapp -o jsonpath="{.items[0].metadata.name}" || echo "flaskapp")
            PORT=$(kubectl -n dev get svc "$SVC" -o jsonpath="{.spec.ports[0].port}")
            kubectl -n dev run curl-tester --rm -i --restart=Never --image=curlimages/curl:8.8.0 -- \
              -s -o /dev/null -w "%{http_code}" http://$SVC.dev.svc.cluster.local:$PORT/ | grep 200
            echo "[OK]   Service healthy (HTTP 200)"
          else
            echo "[INFO] Skipping K8s rollout & smoke test (branch not main)."
          fi
        '''
      }
    }

    stage('Post Actions') {
      steps { echo 'Done.' }
    }
  }
}
