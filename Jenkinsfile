/*
  Jenkinsfile — Linux-style steps (sh). English-only comments inside the file.
  No "docker { }" Groovy APIs are used — only CLI, so no Docker Pipeline plugin required.

  Flow:
  - Checkout → capture GIT_SHA
  - Detect Helm changes (if files under helm/ changed)
  - Helm lint
  - If Helm changed: bump Chart.yaml patch & set appVersion=GIT_SHA, ensure values.yaml image.repo/tag, then package and publish to gh-pages
  - Build & push Docker image (tag = GIT_SHA)
  - Minikube context + k8s preflight
  - Helm deploy + smoke test
*/

pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    skipDefaultCheckout(false)
  }

  environment {
    APP_NAME      = 'flaskapp'                             // must match .Values.app.name
    CHART_DIR     = 'helm/flaskapp'
    DOCKER_IMAGE  = 'erezazu/devops0405-docker-flask-app'  // Docker Hub repo
    K8S_NAMESPACE = 'default'
  }

  stages {

    stage('Checkout SCM') {
      steps { checkout scm }
    }

    stage('Init (capture SHA)') {
      steps {
        script {
          env.GIT_SHA = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
          echo "GIT_SHA = ${env.GIT_SHA}"
        }
      }
    }

    stage('Detect Helm Changes') {
      steps {
        script {
          def out = sh(script: "git log -1 --name-only --pretty=format:''", returnStdout: true).trim()
          echo "Changed files:\n${out}"
          def changed = out.readLines().any { p ->
            def n = (p ?: '').trim().replace('\\','/').toLowerCase()
            n.startsWith('helm/') || n.startsWith('helm/flaskapp/')
          }
          env.HELM_CHANGED = changed ? 'true' : 'false'
          echo "HELM_CHANGED = ${env.HELM_CHANGED}"
        }
      }
    }

    stage('Helm Lint') {
      steps { dir("${CHART_DIR}") { sh 'helm lint .' } }
    }

    stage('Bump Chart Version (patch)') {
      when { expression { env.HELM_CHANGED == 'true' } }
      steps {
        script {
          // ---- Chart.yaml: bump version and set appVersion ----
          def chartPath  = "${CHART_DIR}/Chart.yaml"
          def chartTxt   = readFile(chartPath)
          def chartLines = chartTxt.split(/\r?\n/, -1) as List

          int vIdx = chartLines.findIndexOf { it.trim().toLowerCase().startsWith('version:') }
          if (vIdx >= 0) {
            def cur = chartLines[vIdx].split(':', 2)[1].trim()
            def parts = cur.tokenize('.')
            while (parts.size() < 3) { parts << '0' }
            parts[2] = ((parts[2] as int) + 1).toString()
            chartLines[vIdx] = "version: ${parts.join('.')}"
          } else {
            chartLines << "version: 0.1.0"
          }

          int aIdx = chartLines.findIndexOf { it.trim().toLowerCase().startsWith('appversion:') }
          if (aIdx >= 0) chartLines[aIdx] = "appVersion: ${env.GIT_SHA}"
          else chartLines << "appVersion: ${env.GIT_SHA}"
          writeFile file: chartPath, text: chartLines.join('\n')

          // ---- values.yaml: ensure image.repository & image.tag ----
          def valuesPath = "${CHART_DIR}/values.yaml"
          def lines = readFile(valuesPath).split(/\r?\n/, -1) as List
          boolean inImage = false
          int imageIndent = 0
          boolean repoSet = false
          boolean tagSet  = false
          List out = []

          lines.each { line ->
            String trimmed = line.trim()
            int leadLen = Math.max(0, line.length() - trimmed.length())

            if (!inImage && trimmed.startsWith('image:')) {
              inImage = true; imageIndent = leadLen; repoSet = false; tagSet = false
              out << line; return
            }
            if (inImage) {
              // leaving image block?
              if (trimmed && leadLen <= imageIndent) {
                def sp = ' ' * (imageIndent + 2)
                if (!repoSet) out << "${sp}repository: ${env.DOCKER_IMAGE}"
                if (!tagSet)  out << "${sp}tag: \"${env.GIT_SHA}\""
                inImage = false
                out << line; return
              }
              if (trimmed.startsWith('repository:')) {
                out << (' ' * (imageIndent + 2)) + "repository: ${env.DOCKER_IMAGE}"; repoSet = true; return
              }
              if (trimmed.startsWith('tag:')) {
                out << (' ' * (imageIndent + 2)) + "tag: \"${env.GIT_SHA}\""; tagSet = true; return
              }
              out << line; return
            }
            out << line
          }
          if (inImage) {
            def sp = ' ' * (imageIndent + 2)
            if (!repoSet) out << "${sp}repository: ${env.DOCKER_IMAGE}"
            if (!tagSet)  out << "${sp}tag: \"${env.GIT_SHA}\""
          }
          writeFile file: valuesPath, text: out.join('\n')

          echo "Chart and values updated for ${env.GIT_SHA}"
        }
      }
    }

    stage('Package Chart') {
      when { expression { env.HELM_CHANGED == 'true' } }
      steps {
        dir("${CHART_DIR}") { sh 'helm package .' }
        archiveArtifacts artifacts: "${CHART_DIR}/*.tgz", fingerprint: true
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
            git worktree add gh-pages gh-pages || true
            cp helm/flaskapp/*.tgz gh-pages/
            cd gh-pages
            git add .
            git commit -m "Publish Helm chart" || true
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
      steps { sh 'minikube update-context || true' }
    }

    stage('K8s Preflight') {
      steps { sh 'kubectl cluster-info && kubectl get nodes' }
    }

    stage('Deploy to minikube') {
      steps {
        sh '''
          set -e
          helm upgrade --install ${APP_NAME} ${CHART_DIR} \
            --namespace ${K8S_NAMESPACE} --create-namespace \
            --set image.repository=${DOCKER_IMAGE} \
            --set image.tag=${GIT_SHA} \
            --set image.pullPolicy=IfNotPresent
        '''
      }
    }

    stage('Smoke Test') {
      steps {
        sh '''
          set -e
          kubectl -n ${K8S_NAMESPACE} rollout status deploy/${APP_NAME} --timeout=120s
          NODEPORT=$(kubectl -n ${K8S_NAMESPACE} get svc ${APP_NAME} -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || true)
          if [ -z "$NODEPORT" ]; then
            echo "Service ${APP_NAME} not found or has no nodePort"
            kubectl -n ${K8S_NAMESPACE} get svc
            exit 1
          fi
          IP=$(minikube ip)
          # try /health, fallback to root
          curl -sf "http://$IP:$NODEPORT/health" || curl -sf "http://$IP:$NODEPORT/" || (kubectl -n ${K8S_NAMESPACE} logs deploy/${APP_NAME} --tail=50; exit 1)
        '''
      }
    }
  }

  post {
    success { echo "OK: HELM_CHANGED=${env.HELM_CHANGED}, SHA=${env.GIT_SHA}" }
    always  { cleanWs() }
  }
}