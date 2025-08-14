pipeline {
  agent any
  options {
    timestamps()
    disableConcurrentBuilds()
  }

  environment {
    APP_NAME         = "flaskapp"
    REGISTRY         = "docker.io"
    DOCKERHUB_USER   = "erezazu"
    IMAGE_REPO       = "${REGISTRY}/${DOCKERHUB_USER}/devops0405-docker-flask-app"

    HELM_CHART_DIR    = "helm/flaskapp"
    HELM_PACKAGE_DIR  = "helm/dist"
    NAMESPACE         = "dev"
    BUMP_HELM_VERSION = "true"
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Build Docker Image') {
      steps {
        script {
          env.IMAGE_TAG = sh(script: "git rev-parse --short=7 HEAD", returnStdout: true).trim()
        }
        sh '''
          echo "Building image: ${IMAGE_REPO}:${IMAGE_TAG}"
          docker build -f App/Dockerfile -t ${IMAGE_REPO}:${IMAGE_TAG} App
          docker tag ${IMAGE_REPO}:${IMAGE_TAG} ${IMAGE_REPO}:latest
        '''
      }
    }

    stage('Test') {
      steps {
        sh 'echo "No unit tests yet - skipping (course project)"; true'
      }
    }

    stage('Push Docker Image') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DU', passwordVariable: 'DP')]) {
          sh '''
            echo "${DP}" | docker login -u "${DU}" --password-stdin ${REGISTRY}
            docker push ${IMAGE_REPO}:${IMAGE_TAG}
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

    stage('Helm Version Bump (only if helm/ changed)') {
      when { 
        allOf { expression { env.BUMP_HELM_VERSION == "true" }; changeset "helm/**" }
      }
      steps {
        sh '''
          set -e
          CHART_FILE="${HELM_CHART_DIR}/Chart.yaml"

          CURR=$(grep '^version:' "${CHART_FILE}" | awk '{print $2}')
          IFS='.' read -r MA mi pa <<EOF
${CURR}
EOF
          pa=$((pa+1))
          NEW="${MA}.${mi}.${pa}"

          sed -i "s/^version:.*/version: ${NEW}/" "${CHART_FILE}"
          if grep -q '^appVersion:' "${CHART_FILE}"; then
            sed -i "s/^appVersion:.*/appVersion: ${NEW}/" "${CHART_FILE}"
          else
            echo "appVersion: ${NEW}" >> "${CHART_FILE}"
          fi

          echo "Helm chart version bumped: ${CURR} -> ${NEW}"
          grep -E '^(version|appVersion):' "${CHART_FILE}"
        '''
      }
    }

    stage('Helm Package (only if helm/ changed)') {
      when { changeset "helm/**" }
      steps {
        sh '''
          mkdir -p ${HELM_PACKAGE_DIR}
          helm package ${HELM_CHART_DIR} -d ${HELM_PACKAGE_DIR}
          ls -l ${HELM_PACKAGE_DIR}
        '''
        archiveArtifacts artifacts: "${HELM_PACKAGE_DIR}/*.tgz", fingerprint: true
      }
    }

    stage('Helm Publish (OCI) - only if helm/ changed') {
      when { changeset "helm/**" }
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DU', passwordVariable: 'DP')]) {
          sh '''
            set -e
            helm registry login -u "${DU}" -p "${DP}" registry-1.docker.io
            CHART_TGZ=$(ls -1 ${HELM_PACKAGE_DIR}/*.tgz | head -n1)
            echo "Pushing chart: ${CHART_TGZ}"
            helm push "${CHART_TGZ}" oci://registry-1.docker.io/${DOCKERHUB_USER}/charts
          '''
        }
      }
    }

    stage('Deploy to Kubernetes (main only)') {
      when { anyOf { branch 'main'; branch 'master' } }
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KCFG')]) {
          sh '''
            export KUBECONFIG="${KCFG}"
            helm upgrade --install ${APP_NAME} ${HELM_CHART_DIR}               --namespace ${NAMESPACE} --create-namespace               --set image.repository=${IMAGE_REPO}               --set image.tag=${IMAGE_TAG}
          '''
        }
      }
    }
  }

  post {
    success { echo "Pipeline finished successfully ✅" }
    failure { echo "Pipeline failed ❌ — check the logs" }
    always  { sh 'echo "Done."' }
  }
}
