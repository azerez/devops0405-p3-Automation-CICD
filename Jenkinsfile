pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  parameters {
    booleanParam(name: 'FORCE_HELM', defaultValue: false, description: 'Force Helm stages even if helm/** did not change')
  }

  environment {
    // Docker image registry + repo
    REGISTRY              = 'docker.io'
    IMAGE_REPO            = 'erezazu/devops0405-docker-flask-app'

    // Helm chart
    HELM_CHART_DIR        = 'helm/flaskapp'
    CHART_NAME            = 'flaskapp'

    // Namespaces / deploy
    NAMESPACE             = 'dev'

    // Credentials IDs in Jenkins
    DOCKER_CRED_ID        = 'docker-hub-creds'     // Username + Password (DockerHub)
    GITHUB_TOKEN_ID       = 'github-token'         // Secret Text (GitHub PAT)
    KUBECONFIG_ID         = 'kubeconfig'           // File credential

    // GitHub username used for push when using PAT as Secret Text
    GIT_USER              = 'azerez'
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
          env.IMAGE_TAG = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
        }
        sh '''
          set -e
          echo "Building image: ${REGISTRY}/${IMAGE_REPO}:${IMAGE_TAG}"
          docker build -f App/Dockerfile -t ${REGISTRY}/${IMAGE_REPO}:${IMAGE_TAG} App
          docker tag ${REGISTRY}/${IMAGE_REPO}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_REPO}:latest
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
        withCredentials([usernamePassword(credentialsId: env.DOCKER_CRED_ID, usernameVariable: 'DU', passwordVariable: 'DP')]) {
          sh '''
            set -e
            echo "$DP" | docker login -u "$DU" --password-stdin ${REGISTRY}
            docker push ${REGISTRY}/${IMAGE_REPO}:${IMAGE_TAG}
            docker push ${REGISTRY}/${IMAGE_REPO}:latest
          '''
        }
      }
    }

    stage('Helm Lint') {
      steps {
        sh 'helm lint ${HELM_CHART_DIR}'
      }
    }

    stage('Helm Version Bump (only if helm/** changed or forced)') {
      when {
        anyOf {
          expression { return params.FORCE_HELM }
          expression { return sh(script: "git diff --name-only HEAD~1 2>/dev/null | grep '^helm/' -q || true", returnStatus: true) == 0 }
        }
      }
      steps {
        sh '''
          set -e
          CHART_FILE="${HELM_CHART_DIR}/Chart.yaml"
          if [ ! -f "$CHART_FILE" ]; then
            echo "ERROR: Chart file not found: $CHART_FILE" >&2
            exit 1
          fi

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

          echo "Helm chart version bumped: $CURR -> $NEW"
          echo -n "$NEW" > .helm_new_version
        '''
        script { env.BUMPED_HELM_VERSION = readFile('.helm_new_version').trim() }
      }
    }

    stage('Commit Helm Version to Git (Option A)') {
      when {
        anyOf {
          expression { return params.FORCE_HELM }
          expression { return fileExists('.helm_new_version') }
        }
      }
      steps {
        withCredentials([string(credentialsId: env.GITHUB_TOKEN_ID, variable: 'GTOKEN')]) {
          sh '''
            set -e
            git config user.name "jenkins-bot"
            git config user.email "ci@local"

            # Re-point origin to use PAT auth (Secret Text)
            origin=$(git config --get remote.origin.url)
            origin_auth=${origin/https:\/\//https:\/\/${GIT_USER}:${GTOKEN}@}
            git remote set-url origin "$origin_auth"

            git add "${HELM_CHART_DIR}/Chart.yaml"
            if git diff --cached --quiet; then
              echo "Nothing to commit (no Helm version change)."
            else
              VERSION=$(cat .helm_new_version)
              git commit -m "ci(helm): bump chart to ${VERSION} [skip ci]"
              git push origin HEAD:main
            fi
          '''
        }
      }
    }

    stage('Helm Package (only if helm/** changed or forced)') {
      when {
        anyOf {
          expression { return params.FORCE_HELM }
          expression { return fileExists('.helm_new_version') }
        }
      }
      steps {
        sh '''
          set -e
          mkdir -p helm/dist
          helm package ${HELM_CHART_DIR} -d helm/dist
          ls -l helm/dist
        '''
        archiveArtifacts artifacts: 'helm/dist/*.tgz', onlyIfSuccessful: true
      }
    }

    stage('Helm Publish (OCI) - only if helm/** changed or forced') {
      when {
        anyOf {
          expression { return params.FORCE_HELM }
          expression { return fileExists('.helm_new_version') }
        }
      }
      steps {
        withCredentials([usernamePassword(credentialsId: env.DOCKER_CRED_ID, usernameVariable: 'DU', passwordVariable: 'DP')]) {
          sh '''
            set -e
            helm registry login -u "$DU" -p "$DP" registry-1.docker.io
            CHART_TGZ=$(ls -1 helm/dist/*.tgz | head -n1)
            echo "Pushing chart: $CHART_TGZ"
            helm push "$CHART_TGZ" oci://registry-1.docker.io/erezazu
          '''
        }
      }
    }

    stage('Deploy to Kubernetes (main only)') {
      when { branch 'main' }
      steps {
        withCredentials([file(credentialsId: env.KUBECONFIG_ID, variable: 'KCFG')]) {
          sh '''
            set -e
            export KUBECONFIG="$KCFG"
            helm upgrade --install ${CHART_NAME} ${HELM_CHART_DIR}               --namespace ${NAMESPACE} --create-namespace               --set image.repository=${REGISTRY}/${IMAGE_REPO}               --set image.tag=${IMAGE_TAG}
          '''
        }
      }
    }

    stage('Declarative: Post Actions') {
      steps {
        sh 'echo Done.'
        echo currentBuild.currentResult == 'SUCCESS' ? 'Pipeline finished successfully ✅' : 'Pipeline failed ❌ — check the logs'
      }
    }
  }
}
