/*
  Jenkinsfile — DevOps Course Project (Phase 3)
  -------------------------------------------------
  This pipeline builds and pushes a Docker image, runs Helm lint,
  bumps the Helm chart version when helm/** changed (or on demand),
  packages and publishes the chart to Docker Hub (OCI), commits the
  bumped version back to Git (Option A), and deploys to Kubernetes.

  Toggles (Build with Parameters):
  - FORCE_HELM_PACKAGE: package/publish the chart even if helm/** did not change.
  - FORCE_HELM_BUMP: bump chart version even if helm/** did not change.
  - PERSIST_HELM_VERSION_TO_GIT (default=true): commit the bumped Chart.yaml back to Git.
*/

pipeline {
  agent any

  parameters {
    booleanParam(name: 'FORCE_HELM_PACKAGE', defaultValue: false, description: 'Package & publish Helm chart even if helm/** did not change')
    booleanParam(name: 'FORCE_HELM_BUMP', defaultValue: false, description: 'Bump Helm chart version even if helm/** did not change')
    // Option A enabled by default
    booleanParam(name: 'PERSIST_HELM_VERSION_TO_GIT', defaultValue: true, description: 'Commit bumped Chart.yaml back to Git (keeps Git in sync)')
  }

  environment {
    // Docker image registry and repo
    REGISTRY           = 'docker.io'
    IMAGE_REPO         = 'erezazu/devops0405-docker-flask-app'  // <-- adjust if needed

    // Credentials IDs that already exist in Jenkins
    DOCKER_CREDS_ID    = 'docker-hub-creds'   // Username/Password for Docker Hub
    KUBECONFIG_CRED_ID = 'kubeconfig'         // "Secret file" holding kubeconfig for Minikube
    GITHUB_CRED_ID     = 'github-token'       // Username/Password (or PAT as password)

    // Helm chart paths
    HELM_CHART_DIR     = 'helm/flaskapp'
    HELM_PACKAGE_DIR   = 'helm/dist'

    // Kubernetes target
    NAMESPACE          = 'dev'

    // Repo (HTTP URL) to push back to. Change if your repo path differs.
    GIT_HTTP_URL       = 'https://github.com/azerez/devops0405-p3-Automation-CICD.git'
  }

  options {
    timestamps()
  }

  stages {

    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Build Docker Image') {
      steps {
        script {
          env.GIT_SHA = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
        }
        sh '''
          echo "Building image: ${REGISTRY}/${IMAGE_REPO}:${GIT_SHA}"
          docker build -f App/Dockerfile -t ${REGISTRY}/${IMAGE_REPO}:${GIT_SHA} App
          docker tag ${REGISTRY}/${IMAGE_REPO}:${GIT_SHA} ${REGISTRY}/${IMAGE_REPO}:latest
        '''
      }
    }

    stage('Test') {
      steps {
        sh '''
          echo "No unit tests yet - skipping (course project)"
          true
        '''
      }
    }

    stage('Push Docker Image') {
      steps {
        withCredentials([usernamePassword(credentialsId: env.DOCKER_CREDS_ID,
                                          usernameVariable: 'DU', passwordVariable: 'DP')]) {
          sh '''
            echo "$DP" | docker login -u "$DU" --password-stdin ${REGISTRY}
            docker push ${REGISTRY}/${IMAGE_REPO}:${GIT_SHA}
            docker push ${REGISTRY}/${IMAGE_REPO}:latest
          '''
        }
      }
    }

    stage('Helm Lint') {
      steps {
        sh "helm lint ${HELM_CHART_DIR}"
      }
    }

    stage('Helm Version Bump (only if helm/** changed or forced)') {
      when {
        anyOf {
          changeset pattern: 'helm/**', comparator: 'ANT'
          expression { return params.FORCE_HELM_BUMP }
        }
      }
      steps {
        // Simple PATCH bump: X.Y.Z -> X.Y.(Z+1). Also keeps appVersion aligned.
        sh '''
          set -e
          CHART_FILE='${HELM_CHART_DIR}/Chart.yaml'
          CURR=$(grep '^version:' "$CHART_FILE" | awk '{print $2}')
          IFS=. read -r MA mi pa <<<"$CURR"
          pa=$((pa+1))
          NEW="${MA}.${mi}.${pa}"

          # Update version and appVersion (create appVersion if missing)
          sed -i "s/^version:.*/version: ${NEW}/" "$CHART_FILE"
          if grep -q '^appVersion:' "$CHART_FILE"; then
            sed -i "s/^appVersion:.*/appVersion: ${NEW}/" "$CHART_FILE"
          else
            echo "appVersion: ${NEW}" >> "$CHART_FILE"
          fi

          echo "Helm chart version bumped: ${CURR} -> ${NEW}"
          grep -E '^(version|appVersion):' "$CHART_FILE"
        '''
      }
    }

    stage('Commit Helm Version to Git (Option A)') {
      when {
        allOf {
          anyOf {
            changeset pattern: 'helm/**', comparator: 'ANT'
            expression { return params.FORCE_HELM_BUMP }
          }
          expression { return params.PERSIST_HELM_VERSION_TO_GIT }
        }
      }
      steps {
        withCredentials([usernamePassword(credentialsId: env.GITHUB_CRED_ID,
                                          usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
          sh '''
            set -e
            CHART_FILE='${HELM_CHART_DIR}/Chart.yaml'

            # Commit only if the chart file actually changed
            if git diff --quiet -- "$CHART_FILE"; then
              echo "No Chart.yaml changes detected — skipping commit."
              exit 0
            fi

            NEW_VER=$(awk '/^version:/{print $2}' "$CHART_FILE")

            git config user.name  "jenkins"
            git config user.email "jenkins@local"

            # Ensure we push back to the correct remote over HTTPS with token
            git remote set-url origin "https://${GIT_USER}:${GIT_TOKEN}@${GIT_HTTP_URL#https://}"

            # Rebase to avoid non-fast-forward (in case someone else pushed)
            git pull --rebase origin "${BRANCH_NAME}" || true

            git add "$CHART_FILE"
            git commit -m "chore(helm): bump chart version to ${NEW_VER}" || true
            git push origin HEAD:"${BRANCH_NAME}"
          '''
        }
      }
    }

    stage('Helm Package (only if helm/** changed or forced)') {
      when {
        anyOf {
          changeset pattern: 'helm/**', comparator: 'ANT'
          expression { return params.FORCE_HELM_PACKAGE || params.FORCE_HELM_BUMP }
        }
      }
      steps {
        sh '''
          set -e
          mkdir -p ${HELM_PACKAGE_DIR}
          helm package ${HELM_CHART_DIR} -d ${HELM_PACKAGE_DIR}
          ls -l ${HELM_PACKAGE_DIR}
        '''
        archiveArtifacts artifacts: "${HELM_PACKAGE_DIR}/*.tgz", fingerprint: true
      }
    }

    stage('Helm Publish (OCI) - only if helm/** changed or forced') {
      when {
        anyOf {
          changeset pattern: 'helm/**', comparator: 'ANT'
          expression { return params.FORCE_HELM_PACKAGE || params.FORCE_HELM_BUMP }
        }
      }
      steps {
        withCredentials([usernamePassword(credentialsId: env.DOCKER_CREDS_ID,
                                          usernameVariable: 'DU', passwordVariable: 'DP')]) {
          sh '''
            set -e
            # Login to Docker Hub registry (OCI endpoint)
            helm registry login -u "$DU" -p "$DP" registry-1.docker.io

            # Push the freshly packaged chart to OCI: oci://registry-1.docker.io/<user>
            CHART_TGZ=$(ls -1 ${HELM_PACKAGE_DIR}/*.tgz | head -n1)
            echo "Pushing chart: ${CHART_TGZ}"
            helm push "${CHART_TGZ}" oci://registry-1.docker.io/erezazu
          '''
        }
      }
    }

    stage('Deploy to Kubernetes (main only)') {
      when { anyOf { branch 'main'; branch 'master' } }
      steps {
        withCredentials([file(credentialsId: env.KUBECONFIG_CRED_ID, variable: 'KCFG')]) {
          sh '''
            set -e
            export KUBECONFIG="${KCFG}"

            # If the cluster is unreachable (e.g., Minikube is stopped), skip deploy gracefully.
            if ! kubectl version --short >/dev/null 2 &> /dev/null; then
              echo "Kubernetes cluster not reachable — skipping deploy."
              exit 0
            fi

            helm upgrade --install flaskapp ${HELM_CHART_DIR}               --namespace ${NAMESPACE} --create-namespace               --set image.repository=${REGISTRY}/${IMAGE_REPO}               --set image.tag=${GIT_SHA}
          '''
        }
      }
    }
  }

  post {
    always {
      sh 'echo Done.'
    }
    success {
      echo 'Pipeline finished successfully ✅'
    }
    failure {
      echo 'Pipeline failed ❌ — check the logs'
    }
  }
}
