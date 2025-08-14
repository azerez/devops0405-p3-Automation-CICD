\
pipeline {
  agent any

  options {
    timestamps()
  }

  parameters {
    booleanParam(name: 'FORCE_HELM', defaultValue: false, description: 'Force Helm stages even if no files under helm/** changed')
  }

  environment {
    // --- Docker image info
    DOCKER_NAMESPACE   = 'erezazu'
    IMAGE_NAME         = 'devops0405-docker-flask-app'
    DOCKER_IMAGE       = "docker.io/${DOCKER_NAMESPACE}/${IMAGE_NAME}"

    // --- Helm info
    CHART_NAME         = 'flaskapp'
    HELM_CHART_DIR     = "helm/${env.CHART_NAME}"
    HELM_PACKAGE_DIR   = 'helm/dist'
    OCI_REPO           = 'erezazu'          // > Push Helm chart to oci://registry-1.docker.io/erezazu

    // --- K8s
    NAMESPACE          = 'dev'

    // --- Git
    GIT_USER           = 'azerez'           // <== change if your GitHub username is different
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
          echo "Building image: ${DOCKER_IMAGE}:${env.SHORT_SHA}"
        }
        sh '''
          docker build -f App/Dockerfile -t "${DOCKER_IMAGE}:${SHORT_SHA}" App
          docker tag "${DOCKER_IMAGE}:${SHORT_SHA}" "${DOCKER_IMAGE}:latest"
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
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DU', passwordVariable: 'DP')]) {
          sh '''
            echo "${DP}" | docker login -u "${DU}" --password-stdin docker.io
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
      when {
        anyOf {
          expression { return params.FORCE_HELM }
          expression { sh(returnStatus: true, script: "git diff --name-only HEAD~1..HEAD | grep -E '^helm/' >/dev/null 2>&1") == 0 }
        }
      }
      steps {
        sh '''
          set -e
          CHART_FILE="${HELM_CHART_DIR}/Chart.yaml"
          [ ! -f "${CHART_FILE}" ] && { echo "Chart file not found: ${CHART_FILE}"; exit 1; }

          CURR=$(grep '^version:' "${CHART_FILE}" | awk '{print $2}')
          IFS=. read -r MA mi pa <<EOF
${CURR}
EOF
          : "${pa:=0}"
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

    stage('Commit Helm Version to Git (Option A)') {
      when {
        anyOf {
          expression { return params.FORCE_HELM }
          expression { sh(returnStatus: true, script: "git diff --name-only HEAD~1..HEAD | grep -E '^helm/' >/dev/null 2>&1") == 0 }
        }
      }
      steps {
        withCredentials([string(credentialsId: 'github-token', variable: 'GTOKEN')]) {
          sh '''
            set -e

            git config user.email "ci@${GIT_USER}.local"
            git config user.name  "CI Bot"

            origin=$(git config --get remote.origin.url)
            # Normalize possible git@github.com:owner/repo.git to https://github.com/owner/repo.git
            origin=$(echo "$origin" | sed -E 's#^git@github.com:#https://github.com/#')
            # repo_path like: owner/repo(.git)?
            repo_path=$(echo "$origin" | sed -E 's#^https?://[^/]+/##; s#\\.git$##')
            origin_auth="https://${GIT_USER}:${GTOKEN}@github.com/${repo_path}.git"

            git remote set-url origin "$origin_auth"
            git add "${HELM_CHART_DIR}/Chart.yaml" || true

            ver=$(grep '^version:' "${HELM_CHART_DIR}/Chart.yaml" | awk '{print $2}')
            git commit -m "ci(helm): bump chart to ${ver} [skip ci]" || true
            git push origin HEAD:main

            # restore clean remote without token
            git remote set-url origin "https://github.com/${repo_path}.git"
          '''
        }
      }
    }

    stage('Helm Package (only if helm/** changed or forced)') {
      when {
        anyOf {
          expression { return params.FORCE_HELM }
          expression { sh(returnStatus: true, script: "git diff --name-only HEAD~1..HEAD | grep -E '^helm/' >/dev/null 2>&1") == 0 }
        }
      }
      steps {
        sh '''
          set -e
          mkdir -p "${HELM_PACKAGE_DIR}"
          helm package "${HELM_CHART_DIR}" -d "${HELM_PACKAGE_DIR}"
          ls -l "${HELM_PACKAGE_DIR}"
        '''
        archiveArtifacts artifacts: "${HELM_PACKAGE_DIR}/*.tgz", fingerprint: true
      }
    }

    stage('Helm Publish (OCI) - only if helm/** changed or forced') {
      when {
        anyOf {
          expression { return params.FORCE_HELM }
          expression { sh(returnStatus: true, script: "git diff --name-only HEAD~1..HEAD | grep -E '^helm/' >/dev/null 2>&1") == 0 }
        }
      }
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DU', passwordVariable: 'DP')]) {
          sh '''
            set -e
            helm registry login -u "${DU}" -p "${DP}" registry-1.docker.io
            CHART_TGZ=$(ls -1 "${HELM_PACKAGE_DIR}"/*.tgz | head -n1)
            echo "Pushing chart: ${CHART_TGZ}"
            helm push "${CHART_TGZ}" "oci://registry-1.docker.io/${OCI_REPO}"
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
            export KUBECONFIG="${KCFG}"
            helm upgrade --install ${CHART_NAME} ${HELM_CHART_DIR} \
              --namespace ${NAMESPACE} --create-namespace \
              --set image.repository=${DOCKER_IMAGE} \
              --set image.tag=${SHORT_SHA}
          '''
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
