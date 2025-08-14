pipeline {
  agent any

  options {
    timestamps()
    skipDefaultCheckout(false)
  }

  environment {
    APP_NAME      = 'flaskapp'                      // Helm release name
    CHART_DIR     = 'helm/flaskapp'
    DOCKER_IMAGE  = 'erezazu/devops0405-docker-flask-app'
    K8S_NAMESPACE = 'default'
  }

  stages {

    stage('Checkout SCM') {
      steps { checkout scm }
    }

    stage('Init (capture SHA)') {
      steps {
        script {
          // Capture short SHA using sh to avoid Windows bat quirks.
          def shaOut = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
          echo "GIT_SHA = ${shaOut}"
          env.GIT_SHA = shaOut
        }
      }
    }

    stage('Detect Helm Changes') {
      steps {
        script {
          def changed = sh(script: "git log -1 --name-only --pretty=format:", returnStdout: true).trim()
          echo "Changed files:\n${changed}"
          env.HELM_CHANGED = changed.readLines().any { it?.trim()?.startsWith('helm/') } ? 'true' : 'false'
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
          // --------- Chart.yaml ---------
          def chartPath  = "${CHART_DIR}/Chart.yaml"
          def chartTxt   = readFile(chartPath)
          def chartLines = chartTxt.split("\r?\n",-1) as List

          // bump version x.y.z -> x.y.(z+1)
          int vIdx = chartLines.findIndexOf { it.trim().toLowerCase().startsWith('version:') }
          if (vIdx >= 0) {
            def cur = chartLines[vIdx].split(':',2)[1].trim()
            def parts = cur.tokenize('.')
            while (parts.size() < 3) { parts << '0' }
            parts[2] = ((parts[2] as int) + 1).toString()
            chartLines[vIdx] = "version: ${parts.join('.')}"
          }

          // appVersion -> SHA (append if missing)
          int aIdx = chartLines.findIndexOf { it.trim().toLowerCase().startsWith('appversion:') }
          if (aIdx >= 0) chartLines[aIdx] = "appVersion: ${env.GIT_SHA}"
          else chartLines << "appVersion: ${env.GIT_SHA}"
          writeFile file: chartPath, text: chartLines.join('\n')

          // --------- values.yaml ---------
          def valuesPath = "${CHART_DIR}/values.yaml"
          def lines = readFile(valuesPath).split("\r?\n",-1) as List
          boolean inImage = false
          int imageIndent = 0
          boolean repoSet = false
          boolean tagSet  = false
          List out = []

          lines.each { line ->
            String trimmed = line.trim()
            int leadLen = line.length() - trimmed.length()
            if (leadLen < 0) leadLen = 0

            if (!inImage && trimmed.startsWith('image:')) {
              inImage = true
              imageIndent = leadLen
              repoSet = false
              tagSet  = false
              out << line
              return
            }

            if (inImage) {
              if (trimmed && leadLen <= imageIndent) {
                def sp = ''.padRight(imageIndent + 2, ' ' as char)
                if (!repoSet) out << sp + "repository: ${DOCKER_IMAGE}"
                if (!tagSet)  out << sp + "tag: \"${env.GIT_SHA}\""
                inImage = false
                out << line
                return
              }
              if (trimmed.startsWith('repository:')) {
                def sp = ''.padRight(imageIndent + 2, ' ' as char)
                out << sp + "repository: ${DOCKER_IMAGE}"
                repoSet = true
                return
              }
              if (trimmed.startsWith('tag:')) {
                def sp = ''.padRight(imageIndent + 2, ' ' as char)
                out << sp + "tag: \"${env.GIT_SHA}\""
                tagSet = true
                return
              }
              out << line
              return
            }
            out << line
          }
          if (inImage) {
            def sp = ''.padRight(imageIndent + 2, ' ' as char)
            if (!repoSet) out << sp + "repository: ${DOCKER_IMAGE}"
            if (!tagSet)  out << sp + "tag: \"${env.GIT_SHA}\""
          }

          writeFile file: valuesPath, text: out.join('\n')
          echo "Chart.yaml & values.yaml updated for ${env.GIT_SHA}"
        }
      }
    }

    stage('Package Chart') {
      when { expression { env.HELM_CHANGED == 'true' } }
      steps {
        dir("${CHART_DIR}") {
          sh 'helm package .'
        }
        archiveArtifacts artifacts: "${CHART_DIR}/*.tgz", fingerprint: true
      }
    }

    stage('Publish to gh-pages') {
      when { allOf { branch 'main'; expression { env.HELM_CHANGED == 'true' } } }
      steps {
        script {
          sh '''
            set -e
            git config user.email ci-bot@example.com
            git config user.name ci-bot
            git worktree add gh-pages gh-pages
            cp ${CHART_DIR}/*.tgz gh-pages/
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
            docker login -u ${DOCKERHUB_USER} -p ${DOCKERHUB_PASS}
            docker build -f App/Dockerfile -t ${DOCKER_IMAGE}:${GIT_SHA} App
            docker push ${DOCKER_IMAGE}:${GIT_SHA}
          '''
        }
      }
    }

    stage('Fetch kubeconfig from minikube') {
      steps { sh 'minikube update-context' }
    }

    stage('K8s Preflight') {
      steps {
        sh 'kubectl cluster-info'
        sh 'kubectl get nodes'
      }
    }

    stage('Deploy to minikube') {
      steps {
        sh '''
          set -e
          helm upgrade --install ${APP_NAME} ${CHART_DIR}             --namespace ${K8S_NAMESPACE} --create-namespace             --set image.repository=${DOCKER_IMAGE}             --set image.tag=${GIT_SHA}             --set image.pullPolicy=IfNotPresent
        '''
      }
    }

    stage('Smoke Test') {
      steps {
        script {
          sh '''
            set -e
            # Wait for rollout
            kubectl -n ${K8S_NAMESPACE} rollout status deploy/${APP_NAME} --timeout=120s

            # Try to find a Service created by this release
            SVC=$(kubectl -n ${K8S_NAMESPACE} get svc -l app.kubernetes.io/instance=${APP_NAME} -o jsonpath="{.items[0].metadata.name}" || true)

            if [ -n "$SVC" ]; then
              # If service exists and is NodePort, use minikube IP + nodePort
              TYPE=$(kubectl -n ${K8S_NAMESPACE} get svc "$SVC" -o jsonpath="{.spec.type}")
              if [ "$TYPE" = "NodePort" ]; then
                IP=$(minikube ip)
                PORT=$(kubectl -n ${K8S_NAMESPACE} get svc "$SVC" -o jsonpath="{.spec.ports[0].nodePort}")
                echo "Smoke test via NodePort: http://$IP:$PORT/health"
                curl -fsS "http://$IP:$PORT/health"
                exit 0
              fi
            fi

            # Fallback: port-forward the Deployment (works for ClusterIP or no Service)
            echo "Fallback to port-forward (ClusterIP/no Service)"
            kubectl -n ${K8S_NAMESPACE} port-forward deploy/${APP_NAME} 8080:5000 >/tmp/pf.log 2>&1 &
            PF_PID=$!
            # give it a moment to be ready
            sleep 3
            set +e
            curl -fsS http://127.0.0.1:8080/health
            RC=$?
            kill $PF_PID
            wait $PF_PID 2>/dev/null || true
            exit $RC
          '''
        }
      }
    }
  }

  post {
    always { cleanWs() }
  }
}
