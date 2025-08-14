// Jenkins Declarative Pipeline for Docker build, Helm bump/package/publish (OCI), and K8s deploy
// Notes:
// - ANSI color wrapper removed for compatibility (plugin not required).
// - Chart version bumps only when files under helm/** changed OR when FORCE_HELM_PUBLISH=true.
// - Pushes Helm chart to Docker Hub OCI registry (registry-1.docker.io).
// - Commits bumped Chart.yaml back to Git (Option A).
// - Works on agents with bash, docker, git, and helm available (Git-Bash on Windows OK).

pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  parameters {
    booleanParam(name: 'FORCE_HELM_PUBLISH', defaultValue: false, description: 'Force publish Helm chart even if no changes under helm/**')
  }

  environment {
    REGISTRY        = 'docker.io'
    DOCKERHUB_USER  = 'erezazu'
    IMAGE_NAME      = 'devops0405-docker-flask-app'
    DOCKER_IMAGE    = "${env.REGISTRY}/${env.DOCKERHUB_USER}/${env.IMAGE_NAME}"

    // Helm
    HELM_CHART_DIR  = 'helm/flaskapp'
    K8S_NAMESPACE   = 'dev'
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
          env.IMAGE_TAG = sh(script: "git rev-parse --short=7 HEAD", returnStdout: true).trim()
        }
        echo "Building image: ${env.DOCKER_IMAGE}:${env.IMAGE_TAG}"
        sh "docker build -f App/Dockerfile -t ${DOCKER_IMAGE}:${IMAGE_TAG} App"
        sh "docker tag ${DOCKER_IMAGE}:${IMAGE_TAG} ${DOCKER_IMAGE}:latest"
      }
    }

    stage('Test') {
      steps {
        sh "echo 'No unit tests yet - skipping (course project)'; true"
      }
    }

    stage('Push Docker Image') {
      steps {
        withCredentials([string(credentialsId: 'dockerhub-pass', variable: 'DP')]) {
          sh """
            echo "\$DP" | docker login -u ${DOCKERHUB_USER} --password-stdin ${REGISTRY}
            docker push ${DOCKER_IMAGE}:${IMAGE_TAG}
            docker push ${DOCKER_IMAGE}:latest
          """
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
          return params.FORCE_HELM_PUBLISH || sh(script: "git diff --name-only HEAD~1..HEAD | grep -E '^helm/' >/dev/null 2>&1; echo \$?", returnStdout: true).trim() == '0'
        }
      }
      steps {
        sh(script: """
          set -e
          CHART_FILE=${HELM_CHART_DIR}/Chart.yaml
          [ ! -f "\$CHART_FILE" ] && { echo "Chart.yaml not found at \$CHART_FILE"; exit 1; }

          CURR=\$(grep '^version:' "\$CHART_FILE" | awk '{print \$2}')
          IFS=. read -r MA MI PA <<EOF
\${CURR}
EOF
          PA=\$((PA+1))
          NEW="\${MA}.\${MI}.\${PA}"

          sed -i 's/^version:.*/version: '\$NEW'/' "\$CHART_FILE"
          if grep -q '^appVersion:' "\$CHART_FILE"; then
            sed -i 's/^appVersion:.*/appVersion: '\$NEW'/' "\$CHART_FILE"
          else
            printf '\\nappVersion: %s\\n' "\$NEW" >> "\$CHART_FILE"
          fi

          echo "Helm chart version bumped: \${CURR} -> \${NEW}"
          grep -E '^(version|appVersion):' "\$CHART_FILE"
        """)
      }
    }

    stage('Commit Helm Version to Git (Option A)') {
      when {
        expression {
          return params.FORCE_HELM_PUBLISH || sh(script: "git diff --name-only HEAD~1..HEAD | grep -E '^helm/' >/dev/null 2>&1; echo \$?", returnStdout: true).trim() == '0'
        }
      }
      steps {
        withCredentials([usernamePassword(credentialsId: 'github-user-pass', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
          sh(script: """
            set -e
            git config user.email "ci@azerez.local"
            git config user.name  "CI Bot"

            origin=\$(git config --get remote.origin.url)
            # Normalize SSH -> HTTPS (if needed)
            origin=\$(echo "\$origin" | sed -E 's#^git@github.com:#https://github.com/#')
            # Inject credentials
            origin_auth=\$(echo "\$origin" | sed -E 's#^https?://#https://${GIT_USER}:${GIT_PASS}@#')

            git remote set-url origin "\$origin_auth"
            git add ${HELM_CHART_DIR}/Chart.yaml
            ver=\$(grep '^version:' ${HELM_CHART_DIR}/Chart.yaml | awk '{print \$2}')
            git commit -m "ci(helm): bump chart to \$ver [skip ci]" || true
            git push origin HEAD:main
            # Restore clean URL
            git remote set-url origin "\$origin"
          """)
        }
      }
    }

    stage('Helm Package (only if helm/** changed or forced)') {
      when {
        expression {
          return params.FORCE_HELM_PUBLISH || sh(script: "git diff --name-only HEAD~1..HEAD | grep -E '^helm/' >/dev/null 2>&1; echo \$?", returnStdout: true).trim() == '0'
        }
      }
      steps {
        sh """
          set -e
          mkdir -p helm/dist
          helm package ${HELM_CHART_DIR} -d helm/dist
          ls -l helm/dist
        """
        archiveArtifacts artifacts: 'helm/dist/*.tgz', fingerprint: true
      }
    }

    stage('Helm Publish (OCI) - only if helm/** changed or forced)') {
      when {
        expression {
          return params.FORCE_HELM_PUBLISH || sh(script: "git diff --name-only HEAD~1..HEAD | grep -E '^helm/' >/dev/null 2>&1; echo \$?", returnStdout: true).trim() == '0'
        }
      }
      steps {
        withCredentials([string(credentialsId: 'dockerhub-pass', variable: 'DP')]) {
          sh """
            set -e
            helm registry login -u ${DOCKERHUB_USER} -p "\$DP" registry-1.docker.io
            CHART_TGZ=\$(ls -1 helm/dist/*.tgz | tail -n1)
            echo "Pushing chart: \$CHART_TGZ"
            helm push "\$CHART_TGZ" oci://registry-1.docker.io/${DOCKERHUB_USER}
          """
        }
      }
    }

    stage('Deploy to Kubernetes (main only)') {
      when { branch 'main' }
      steps {
        withCredentials([file(credentialsId: 'kubeconfig-jenkins', variable: 'KCFG')]) {
          sh """
            set -e
            export KUBECONFIG="\$KCFG"
            helm upgrade --install flaskapp ${HELM_CHART_DIR} --namespace ${K8S_NAMESPACE} --create-namespace \
              --set image.repository=${DOCKER_IMAGE} --set image.tag=${IMAGE_TAG}
          """
        }
      }
    }
  }

  post {
    always {
      echo 'Done.'
    }
    success {
      echo 'Pipeline finished successfully ✅'
    }
    failure {
      echo 'Pipeline failed ❌ — check the logs'
    }
  }
}
