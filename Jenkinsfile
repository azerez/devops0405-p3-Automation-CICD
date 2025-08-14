/*
 Jenkinsfile — CI/CD for Flask app (Docker + Helm + Minikube)
 -----------------------------------------------------------
 - Builds and pushes a Docker image tagged with the short Git SHA + `latest`.
 - Lints the Helm chart.
 - Bumps the chart version ONLY when files under `helm/**` changed (or FORCE_HELM=true).
 - Commits the bumped Chart.yaml back to GitHub using a PAT (with [skip ci]).
 - Packages and pushes the newest chart to Docker Hub (OCI).
 - Deploys to Minikube (kubeconfig injected from Jenkins credentials).

 Required Jenkins credentials (IDs):
   * dockerhub-cred  -> Username/Password (Docker Hub)
   * github-pat      -> Secret text (GitHub PAT with `repo` scope)
   * kubeconfig      -> Secret file (your Minikube kubeconfig)

 Notes:
   * Change DOCKERHUB_ORG / DOCKER_IMAGE / HELM_CHART_DIR / NAMESPACE if needed.
   * To force Helm publish even when `helm/**` didn’t change, build with FORCE_HELM=true.
*/

pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  parameters {
    booleanParam(
      name: 'FORCE_HELM',
      defaultValue: false,
      description: 'Force Helm bump/package/publish even if no files under helm/** changed'
    )
  }

  environment {
    // --- Image & Helm settings ---
    DOCKERHUB_ORG   = 'erezazu'
    DOCKER_IMAGE    = 'devops0405-docker-flask-app'
    IMAGE_REPO      = "docker.io/${DOCKERHUB_ORG}/${DOCKER_IMAGE}"
    APP_NAME        = 'flaskapp'
    HELM_CHART_DIR  = 'helm/flaskapp'
    HELM_OCI_REPO   = "oci://registry-1.docker.io/${DOCKERHUB_ORG}"
    NAMESPACE       = 'dev'
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
          env.GIT_SHORT_SHA = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
          echo "Building image: ${env.IMAGE_REPO}:${env.GIT_SHORT_SHA}"
        }
        sh """
          docker build -f App/Dockerfile -t ${IMAGE_REPO}:${GIT_SHORT_SHA} App
          docker tag ${IMAGE_REPO}:${GIT_SHORT_SHA} ${IMAGE_REPO}:latest
        """
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
        withCredentials([usernamePassword(credentialsId: 'dockerhub-cred', usernameVariable: 'DHU', passwordVariable: 'DHP')]) {
          sh '''
            echo "$DHP" | docker login -u "$DHU" --password-stdin docker.io
            docker push ${IMAGE_REPO}:${GIT_SHORT_SHA}
            docker push ${IMAGE_REPO}:latest
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
        expression {
          def changed = sh(script: "git diff --name-only HEAD~1..HEAD | grep -E '^helm/' || true", returnStdout: true).trim()
          return (params.FORCE_HELM || changed)
        }
      }
      steps {
        sh '''
          set -e
          CHART_FILE=${HELM_CHART_DIR}/Chart.yaml
          [ ! -f "$CHART_FILE" ] && { echo "Chart.yaml not found at $CHART_FILE"; exit 1; }

          # Read current version
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
        '''
      }
    }

    stage('Commit Helm Version to Git (Option A)') {
      when {
        expression {
          def changed = sh(script: "git diff --name-only HEAD~1..HEAD | grep -E '^helm/' || true", returnStdout: true).trim()
          return (params.FORCE_HELM || changed)
        }
      }
      steps {
        sh "git diff --name-only HEAD~1..HEAD | grep -E '^helm/' || true"
        withCredentials([string(credentialsId: 'github-pat', variable: 'GTOKEN')]) {
          sh '''
            set -e
            git config user.email "ci@local"
            git config user.name "CI Bot"

            origin=$(git config --get remote.origin.url)
            origin=$(echo "$origin" | sed -E 's#^git@github.com:#https://github.com/#')
            repo_path=$(echo "$origin" | sed -E 's#^https?://[^/]+/##; s#\.git$##')
            user=$(echo "$repo_path" | cut -d/ -f1)

            origin_auth="https://${user}:${GTOKEN}@github.com/${repo_path}.git"
            git remote set-url origin "$origin_auth"

            git add ${HELM_CHART_DIR}/Chart.yaml
            ver=$(grep '^version:' ${HELM_CHART_DIR}/Chart.yaml | awk '{print $2}')
            git commit -m "ci(helm): bump chart to ${ver} [skip ci]" || true
            git push origin HEAD:main

            git remote set-url origin "$origin"
          '''
        }
      }
    }

    stage('Helm Package (only if helm/** changed or forced)') {
      when {
        expression {
          def changed = sh(script: "git diff --name-only HEAD~1..HEAD | grep -E '^helm/' || true", returnStdout: true).trim()
          return (params.FORCE_HELM || changed)
        }
      }
      steps {
        sh '''
          set -e
          mkdir -p helm/dist
          helm package ${HELM_CHART_DIR} -d helm/dist
          ls -l helm/dist
        '''
        archiveArtifacts artifacts: 'helm/dist/*.tgz', fingerprint: true
      }
    }

    stage('Helm Publish (OCI) - only if helm/** changed or forced') {
      when {
        expression {
          def changed = sh(script: "git diff --name-only HEAD~1..HEAD | grep -E '^helm/' || true", returnStdout: true).trim()
          return (params.FORCE_HELM || changed)
        }
      }
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub-cred', usernameVariable: 'DHU', passwordVariable: 'DHP')]) {
          sh '''
            set -e
            helm registry login -u "$DHU" -p "$DHP" registry-1.docker.io

            CHART_TGZ=$(ls -1 helm/dist/*.tgz | sort -V | tail -n1)
            echo "Pushing chart: $CHART_TGZ"
            helm push "$CHART_TGZ" ${HELM_OCI_REPO}
          '''
        }
      }
    }

    stage('Deploy to Kubernetes (main only)') {
      when {
        branch 'main'
      }
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KCFG')]) {
          sh '''
            set -e
            export KUBECONFIG="$KCFG"
            helm upgrade --install ${APP_NAME} ${HELM_CHART_DIR} \
              --namespace ${NAMESPACE} --create-namespace \
              --set image.repository=${IMAGE_REPO} \
              --set image.tag=${GIT_SHORT_SHA}
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
      echo 'Done.'
    }
  }
}