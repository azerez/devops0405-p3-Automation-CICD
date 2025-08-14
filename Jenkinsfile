/*
  Jenkinsfile — Windows-friendly (bat + PowerShell), with Helm package publish,
  Docker build & push, deploy to minikube, and smoke test.
  Adds a "Sanitize YAML encoding" step to ensure UTF‑8 (no BOM) for Chart.yaml/values.yaml,
  preventing "invalid trailing UTF-8 octet" in helm package.
*/

pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    skipDefaultCheckout false
  }

  environment {
    APP_NAME      = 'flaskapp'
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
          // Use bat to avoid ANSI control chars on Windows; extract last non-empty line
          def out = bat(script: 'git rev-parse --short HEAD', returnStdout: true)
          def lines = out.readLines().collect{ it?.trim() }.findAll{ it }
          env.GIT_SHA = lines ? lines[-1] : 'unknown'
          echo "GIT_SHA = ${env.GIT_SHA}"
        }
      }
    }

    stage('Helm Lint') {
      steps { dir("${CHART_DIR}") { bat 'helm lint .' } }
    }

    stage('Bump Chart Version (patch)') {
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

    stage('Sanitize YAML encoding (UTF-8 no BOM)') {
      steps {
        // Re-save YAML files as UTF‑8 without BOM to avoid "invalid trailing UTF‑8 octet"
        bat '''
powershell -NoProfile -Command ^
  "$p='helm/flaskapp/values.yaml';" ^
  "$c = Get-Content -Raw $p; " ^
  "[IO.File]::WriteAllText($p, $c, [Text.UTF8Encoding]::new($false))"

powershell -NoProfile -Command ^
  "$p='helm/flaskapp/Chart.yaml';" ^
  "$c = Get-Content -Raw $p; " ^
  "[IO.File]::WriteAllText($p, $c, [Text.UTF8Encoding]::new($false))"
        '''
      }
    }

    stage('Package Chart') {
      steps {
        bat 'helm package -d ".release" "helm/flaskapp"'
      }
    }

    stage('Publish to gh-pages') {
      steps {
        bat '''
@echo off
setlocal enableextensions
git config user.email "ci-bot@example.com"
git config user.name "ci-bot"
git fetch origin gh-pages 1>NUL 2>NUL
git worktree prune 1>NUL 2>NUL
rmdir /S /Q ghp 1>NUL 2>NUL
git worktree add -B gh-pages ghp origin/gh-pages 1>NUL 2>NUL || git worktree add -B gh-pages ghp gh-pages
copy /Y .release\*.tgz ghp\ >NUL
pushd ghp
git add .
git commit -m "Publish Helm chart" || ver >NUL
git push origin gh-pages
popd
endlocal
        '''
      }
    }

    stage('Build & Push Docker') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DOCKERHUB_USER', passwordVariable: 'DOCKERHUB_PASS')]) {
          bat '''
@echo off
setlocal enableextensions
docker login -u %DOCKERHUB_USER% -p %DOCKERHUB_PASS%
docker build -f App/Dockerfile -t %DOCKER_IMAGE%:%GIT_SHA% App
docker push %DOCKER_IMAGE%:%GIT_SHA%
endlocal
          '''
        }
      }
    }

    stage('Deploy to minikube') {
      steps {
        bat '''
@echo off
setlocal enableextensions
helm upgrade --install %APP_NAME% %CHART_DIR% ^
  --namespace %K8S_NAMESPACE% --create-namespace ^
  --set image.repository=%DOCKER_IMAGE% ^
  --set image.tag=%GIT_SHA% ^
  --set image.pullPolicy=IfNotPresent
endlocal
        '''
      }
    }

    stage('Smoke Test') {
      steps {
        bat '''
@echo off
setlocal enableextensions
kubectl -n %K8S_NAMESPACE% rollout status deploy/%APP_NAME% --timeout=120s
for /f "usebackq delims=" %%N in (`kubectl -n %K8S_NAMESPACE% get svc %APP_NAME% -o "jsonpath={.spec.ports[0].nodePort}" 2^>NUL`) do set NODEPORT=%%N
if not defined NODEPORT (
  echo SERVICE %APP_NAME% not found or no NodePort exposed.
  exit /b 1
)
for /f "usebackq delims=" %%I in (`minikube ip`) do set MINIKUBE_IP=%%I
curl -s "http://%MINIKUBE_IP%:%NODEPORT%/health" || exit /b 1
endlocal
        '''
      }
    }
  }

  post {
    success { echo "OK: SHA=${env.GIT_SHA}" }
    always  { cleanWs() }
  }
}
