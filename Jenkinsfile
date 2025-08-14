pipeline {
  agent any

  environment {
    // Use the Docker Hub repo you actually push to in logs
    DOCKER_IMAGE = "erezazu/devops0405-docker-flask-app"
  }

  options {
    timestamps()
    disableConcurrentBuilds()
    skipDefaultCheckout(false)
  }

  stages {
    stage('Checkout SCM') {
      steps { checkout scm }
    }

    stage('Init (capture SHA)') {
      steps {
        script {
          def sha = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
          echo "GIT_SHA = ${sha}"
          env.GIT_SHA = sha
        }
      }
    }

    stage('Detect Helm Changes') {
      steps {
        script {
          def diff = sh(script: "git log -1 --name-only --pretty=format:''", returnStdout: true).trim().split("\n")
          echo "Changed files:\n" + diff.join("\n")
          def changed = diff.any { it?.trim()?.startsWith("helm/") || it?.trim()?.startsWith("helm/flaskapp/") }
          echo "HELM_CHANGED = ${changed}"
          env.HELM_CHANGED = changed ? "true" : "false"
        }
      }
    }

    stage('Helm Lint') {
      steps {
        dir('helm/flaskapp') { sh 'helm lint .' }
      }
    }

    stage('Bump Chart Version (patch)') {
      when { expression { env.HELM_CHANGED == 'true' } }
      steps {
        dir('helm/flaskapp') {
          sh '''
            set -e
            version=$(grep '^version:' Chart.yaml | awk '{print $2}')
            new_version=$(echo "$version" | awk -F. -v OFS=. '{$NF += 1 ; print}')
            sed -i "s/^version:.*/version: ${new_version}/" Chart.yaml

            if grep -qi '^appVersion:' Chart.yaml; then
              sed -i "s/^appVersion:.*/appVersion: ${GIT_SHA}/I" Chart.yaml
            else
              echo "appVersion: ${GIT_SHA}" >> Chart.yaml
            fi

            # Ensure values.yaml has image.repository and image.tag set
            if ! grep -q '^image:' values.yaml; then
              printf "\nimage:\n  repository: %s\n  tag: \"%s\"\n" "${DOCKER_IMAGE}" "${GIT_SHA}" >> values.yaml
            else
              if grep -q '^[[:space:]]*repository:' values.yaml; then
                sed -i "s#^[[:space:]]*repository:.*#  repository: ${DOCKER_IMAGE}#" values.yaml
              else
                sed -i "/^image:/a\  repository: ${DOCKER_IMAGE}" values.yaml
              fi
              if grep -q '^[[:space:]]*tag:' values.yaml; then
                sed -i "s#^[[:space:]]*tag:.*#  tag: \"${GIT_SHA}\"#" values.yaml
              else
                sed -i "/^image:/a\  tag: \"${GIT_SHA}\"" values.yaml
              fi
            fi
          '''
        }
      }
    }

    stage('Package Chart') {
      when { expression { env.HELM_CHANGED == 'true' } }
      steps {
        dir('helm/flaskapp') { sh 'helm package .' }
        archiveArtifacts artifacts: 'helm/flaskapp/*.tgz', fingerprint: true
      }
    }

    stage('Publish to gh-pages') {
      when { expression { env.HELM_CHANGED == 'true' } }
      steps {
        script {
          sh '''
            set -e
            git config user.email "ci-bot@example.com"
            git config user.name "ci-bot"
            git worktree add gh-pages gh-pages
            cp helm/flaskapp/*.tgz gh-pages/
            cd gh-pages
            git add .
            git commit -m "Publish Helm chart"
            git push origin gh-pages
          '''
        }
      }
    }

    stage('Build & Push Docker') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DOCKERHUB_USER', passwordVariable: 'DOCKERHUB_PASS')]) {
          sh '''
            set -e
            docker login -u "$DOCKERHUB_USER" -p "$DOCKERHUB_PASS"
            docker build -f App/Dockerfile -t ${DOCKER_IMAGE}:${GIT_SHA} App
            docker push ${DOCKER_IMAGE}:${GIT_SHA}
          '''
        }
      }
    }

    stage('Fetch kubeconfig from minikube') {
      steps {
        sh 'minikube update-context || true'
      }
    }

    stage('K8s Preflight') {
      steps {
        sh 'kubectl cluster-info && kubectl get nodes'
      }
    }

    stage('Deploy to minikube') {
      steps {
        sh '''
          set -e
          helm upgrade --install flaskapp helm/flaskapp             --namespace default --create-namespace             --set image.repository=${DOCKER_IMAGE}             --set image.tag=${GIT_SHA}             --set image.pullPolicy=IfNotPresent
        '''
      }
    }

    stage('Smoke Test') {
      steps {
        sh '''
          set -e
          kubectl -n default rollout status deploy/flaskapp --timeout=120s
          NODEPORT=$(kubectl -n default get svc flaskapp -o jsonpath="{.spec.ports[0].nodePort}")
          IP=$(minikube ip)
          curl -s "http://${IP}:${NODEPORT}/health" || true
        '''
      }
    }
  }

  post {
    success { echo "OK: HELM_CHANGED=${env.HELM_CHANGED}, SHA=${env.GIT_SHA}" }
    always  { cleanWs() }
  }
}
