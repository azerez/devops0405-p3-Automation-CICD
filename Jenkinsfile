
// Jenkinsfile (Phase 3) — simple CI/CD with Docker + Helm (with version bump)
// NOTE: keep comments and text in English inside this file per course requirement.
//
// What this pipeline does (high-level):
// 1) Checkout
// 2) Build Docker image and tag with the short Git SHA + "latest"
// 3) (Optional) run tests (placeholder)
// 4) Push image to Docker Hub
// 5) Lint Helm chart
// 6) Bump Helm chart version (patch) ONLY if helm/** changed (or forced via parameter)
// 7) (Option A) Commit the bumped Chart.yaml back to Git (so the version is recorded)
// 8) Package the chart and push it to Docker Hub (OCI registry) ONLY if helm/** changed (or forced)
// 9) Deploy to Kubernetes (minikube) with Helm (namespace: dev) using kubeconfig credential
//
// Required Jenkins credentials (create them once in Jenkins > Manage Credentials):
// - id: dockerhub-pass      (Secret text)  → contains your Docker Hub password or access token
// - id: github-user-pass    (Username with password) → GitHub username + PAT (with repo scope)
// - id: kubeconfig-jenkins  (Secret file)  → a kubeconfig file exported from your minikube (path injected at runtime)
//
// If your credentials IDs differ, change them in the withCredentials{} steps below.
//
// Extra knobs for the grader / instructor:
// - parameter FORCE_HELM_PUBLISH=true will force bump + package + push, even if no files under helm/ changed.
// - we also guard each “Option A” Git commit so it only runs if Chart.yaml really changed (no-op otherwise).

pipeline {
  agent any

  options {
    timestamps()
    ansiColor('xterm')
  }

  parameters {
    booleanParam(name: 'FORCE_HELM_PUBLISH', defaultValue: false, description: 'Force Helm bump+publish even if no changes in helm/**')
  }

  environment {
    // Docker / app
    DOCKERHUB_REGISTRY = 'docker.io'
    DOCKERHUB_USER     = 'erezazu'
    DOCKER_IMAGE       = 'docker.io/erezazu/devops0405-docker-flask-app'

    // Helm
    HELM_CHART_DIR     = 'helm/flaskapp'   // the chart lives here
    K8S_NAMESPACE      = 'dev'
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Build Docker Image') {
      steps {
        script {
          env.SHORT_SHA = sh(returnStdout: true, script: 'git rev-parse --short=7 HEAD').trim()
        }
        echo "Building image: ${env.DOCKER_IMAGE}:${env.SHORT_SHA}"
        sh "docker build -f App/Dockerfile -t ${DOCKER_IMAGE}:${SHORT_SHA} App"
        sh "docker tag ${DOCKER_IMAGE}:${SHORT_SHA} ${DOCKER_IMAGE}:latest"
      }
    }

    stage('Test') {
      steps {
        sh 'echo "No unit tests yet - skipping (course project)" && true'
      }
    }

    stage('Push Docker Image') {
      steps {
        withCredentials([string(credentialsId: 'dockerhub-pass', variable: 'DP')]) {
          sh '''
            set -e
            echo "$DP" | docker login -u "$DOCKERHUB_USER" --password-stdin "$DOCKERHUB_REGISTRY"
            docker push "${DOCKER_IMAGE}:${SHORT_SHA}"
            docker push "${DOCKER_IMAGE}:latest"
          '''
        }
      }
    }

    stage('Helm Lint') {
      steps {
        sh 'helm lint "${HELM_CHART_DIR}"'
      }
    }

    stage('Helm Version Bump (only if helm/** changed or forced)') {
      steps {
        sh '''
          set -e
          # Skip if no helm/ changes and not forced
          if [ -z "$(git diff --name-only HEAD~1..HEAD | grep -E '^helm/' || true)" ] && [ "${FORCE_HELM_PUBLISH}" != "true" ]; then
            echo "No helm/ changes and FORCE_HELM_PUBLISH=false — skipping bump."
            exit 0
          fi

          CHART_FILE="${HELM_CHART_DIR}/Chart.yaml"
          if [ ! -f "$CHART_FILE" ]; then
            echo "Chart file not found: $CHART_FILE"
            exit 1
          fi

          CURR=$(grep '^version:' "$CHART_FILE" | awk '{print $2}')
          IFS=. read -r MA mi pa <<< "$CURR"
          : "${pa:=0}"
          pa=$((pa+1))
          NEW="$MA.$mi.$pa"

          # Update version + appVersion (patch bump)
          sed -i "s/^version:.*/version: $NEW/" "$CHART_FILE"
          if grep -q '^appVersion:' "$CHART_FILE"; then
            sed -i "s/^appVersion:.*/appVersion: $NEW/" "$CHART_FILE"
          else
            echo "appVersion: $NEW" >> "$CHART_FILE"
          fi

          echo "Helm chart version bumped: $CURR -> $NEW"
          grep -E '^(version|appVersion):' "$CHART_FILE" || true
        '''
      }
    }

    stage('Commit Helm Version to Git (Option A)') {
      steps {
        // Only commit if Chart.yaml has changes (no-op otherwise)
        sh '''
          set -e
          if git diff --quiet "${HELM_CHART_DIR}/Chart.yaml"; then
            echo "No version change detected — skipping Git commit."
            exit 0
          fi
        '''
        withCredentials([usernamePassword(credentialsId: 'github-user-pass', usernameVariable: 'GIT_USER', passwordVariable: 'GTOKEN')]) {
          sh '''
            set -e

            git config user.email "ci@azerez.local"
            git config user.name  "CI Bot"

            origin="$(git config --get remote.origin.url)"
            # Normalize to https (in case job was created with git@ URL)
            origin="$(echo "$origin" | sed -E 's#^git@github.com:#https://github.com/#')"
            # Embed credentials
            origin_auth="https://${GIT_USER}:${GTOKEN}@${origin#https://}"
            git remote set-url origin "$origin_auth"

            ver=$(grep '^version:' "${HELM_CHART_DIR}/Chart.yaml" | awk '{print $2}')

            git add "${HELM_CHART_DIR}/Chart.yaml"
            git commit -m "ci(helm): bump chart to ${ver} [skip ci]" || true
            git push origin HEAD:main

            # Restore remote URL without credentials
            git remote set-url origin "$origin"
          '''
        }
      }
    }

    stage('Helm Package (only if helm/** changed or forced)') {
      steps {
        sh '''
          set -e
          # Skip if no helm/ changes and not forced
          if [ -z "$(git diff --name-only HEAD~1..HEAD | grep -E '^helm/' || true)" ] && [ "${FORCE_HELM_PUBLISH}" != "true" ]; then
            echo "No helm/ changes and FORCE_HELM_PUBLISH=false — skipping package."
            exit 0
          fi

          mkdir -p helm/dist
          helm package "${HELM_CHART_DIR}" -d helm/dist
          ls -l helm/dist
        '''
        archiveArtifacts artifacts: 'helm/dist/*.tgz', fingerprint: true
      }
    }

    stage('Helm Publish (OCI) - only if helm/** changed or forced') {
      steps {
        sh '''
          set -e
          if [ -z "$(git diff --name-only HEAD~1..HEAD | grep -E '^helm/' || true)" ] && [ "${FORCE_HELM_PUBLISH}" != "true" ]; then
            echo "No helm/ changes and FORCE_HELM_PUBLISH=false — skipping helm push."
            exit 0
          fi
        '''
        withCredentials([string(credentialsId: 'dockerhub-pass', variable: 'DP')]) {
          sh '''
            set -e
            helm registry login -u "${DOCKERHUB_USER}" -p "${DP}" registry-1.docker.io
            CHART_TGZ=$(ls -1t helm/dist/*.tgz | head -n1)
            echo "Pushing chart: ${CHART_TGZ}"
            # Push to Docker Hub OCI namespace: docker.io/<user>/<chartName>:<version>
            helm push "${CHART_TGZ}" oci://registry-1.docker.io/${DOCKERHUB_USER}
          '''
        }
      }
    }

    stage('Deploy to Kubernetes (main only)') {
      when { branch 'main' }
      steps {
        withCredentials([file(credentialsId: 'kubeconfig-jenkins', variable: 'KCFG')]) {
          sh '''
            set -e
            export KUBECONFIG="$KCFG"
            helm upgrade --install flaskapp "${HELM_CHART_DIR}"               --namespace "${K8S_NAMESPACE}"               --create-namespace               --set image.repository="${DOCKER_IMAGE}"               --set image.tag="${SHORT_SHA}"
          '''
        }
      }
    }
  }

  post {
    success {
      echo 'Pipeline finished successfully ✅'
    }
    failure {
      echo 'Pipeline failed ❌ — check the logs'
    }
    always {
      sh 'echo Done.'
    }
  }
}
