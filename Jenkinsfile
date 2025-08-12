pipeline {
  agent any

  options {
    timestamps()
    skipDefaultCheckout(false)
  }

  environment {
    APP_NAME      = 'flaskapp'
    CHART_DIR     = 'helm/flaskapp'
    RELEASE_DIR   = '.release'
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
          def out = bat(script: 'git rev-parse --short HEAD', returnStdout: true)
          def lines = out.readLines().collect { it?.trim() }.findAll { it }
          env.GIT_SHA = lines ? lines[-1] : 'unknown'
          echo "GIT_SHA = ${env.GIT_SHA}"
        }
      }
    }

    stage('Detect Changes') {
      steps {
        script {
          def hasPrev = (bat(script: 'git rev-parse HEAD~1', returnStatus: true) == 0)
          def diffCmd = hasPrev ? 'git diff --name-only HEAD~1 HEAD' : 'git show --name-only --pretty='
          def changed = bat(script: diffCmd, returnStdout: true)
                         .readLines()
                         .collect { it?.trim()?.replace('\\','/') }
                         .findAll { it }
          env.HELM_CHANGED = changed.any { it.startsWith('helm/') } ? '1' : '0'
          env.APP_CHANGED  = changed.any { it.startsWith('App/')  } ? '1' : '0'
          echo "HELM_CHANGED=${env.HELM_CHANGED}, APP_CHANGED=${env.APP_CHANGED}"
        }
      }
    }

    stage('Helm Lint') {
      when { expression { env.HELM_CHANGED == '1' } }
      steps { dir("${CHART_DIR}") { bat 'helm lint .' } }
    }

    stage('Bump Chart Version (patch)') {
      when { expression { env.HELM_CHANGED == '1' } }
      steps {
        script {
          // ---- Chart.yaml ----
          def chartPath  = "${CHART_DIR}/Chart.yaml"
[O          def chartTxt   = readFile(chartPath)
          def chartLines = chartTxt.split(/\r?\n/, -1) as List

          int vIdx = chartLines.findIndexOf { it.trim().toLowerCase().startsWith('version:') }
          if (vIdx >= 0) {
            def cur = chartLines[vIdx].split(':', 2)[1].trim()
            def parts = cur.tokenize('.')
            while (parts.size() < 3) { parts << '0' }
            parts[2] = ((parts[2] as int) + 1).toString()
            chartLines[vIdx] = "version: ${parts.join('.')}"
          } else {
            echo "WARN: version not found in Chart.yaml – leaving as-is"
          }

          int aIdx = chartLines.findIndexOf { it.trim().toLowerCase().startsWith('appversion:') }
          if (aIdx >= 0) {
            chartLines[aIdx] = "appVersion: ${env.GIT_SHA}"
          } else {
            chartLines << "appVersion: ${env.GIT_SHA}"
          }
          writeFile file: chartPath, text: chartLines.join('\n')

          // ---- values.yaml ----
          def valuesPath = "${CHART_DIR}/values.yaml"
          def lines = readFile(valuesPath).split(/\r?\n/, -1) as List
          boolean inImage = false
          int imageIndent = 0
          boolean repoSet = false
          boolean tagSet  = false
          List out = []

          lines.each { line ->
            String trimmed = line.trim()
            int leadLen = line.length() - trimmed.length(); if (leadLen < 0) leadLen = 0

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
                def sp=''; for (int i=0; i<imageIndent+2; i++) sp+=' '
                if (!repoSet) out << sp + "repository: ${DOCKER_IMAGE}"
                if (!tagSet)  out << sp + "tag: \"${env.GIT_SHA}\""
                inImage = false
                out << line
                return
              }

              if (trimmed.startsWith('repository:')) {
                def sp=''; for (int i=0; i<imageIndent+2; i++) sp+=' '
                out << sp + "repository: ${DOCKER_IMAGE}"
                repoSet = true
                return
              }
              if (trimmed.startsWith('tag:')) {
                def sp=''; for (int i=0; i<imageIndent+2; i++) sp+=' '
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
            def sp=''; for (int i=0; i<imageIndent+2; i++) sp+=' '
            if (!repoSet) out << sp + "repository: ${DOCKER_IMAGE}"
            if (!tagSet)  out << sp + "tag: \"${env.GIT_SHA}\""
          }

          writeFile file: valuesPath, text: out.join('\n')
          echo "Chart and values updated for ${env.GIT_SHA}"
        }
      }
    }

    stage('Package Chart') {
      when { expression { env.HELM_CHANGED == '1' } }
      steps { bat "helm package -d \"${RELEASE_DIR}\" \"${CHART_DIR}\"" }
    }

    stage('Publish to gh-pages') {
      when { allOf { branch 'main'; expression { env.HELM_CHANGED == '1' } } }
      steps {
        withCredentials([string(credentialsId: 'github-token', variable: 'GH_TOKEN')]) {
          bat '''
@echo off
setlocal enableextensions

if not exist .release\\*.tgz (
  echo ERROR: no .tgz under .release
  exit /b 1
)

git fetch origin gh-pages 1>NUL 2>NUL || ver >NUL
git worktree prune 1>NUL 2>NUL
rmdir /S /Q ghp 1>NUL 2>NUL

git worktree add -B gh-pages ghp origin/gh-pages 1>NUL 2>NUL || git worktree add -B gh-pages ghp gh-pages

if not exist ghp\\docs mkdir ghp\\docs
copy /Y .release\\*.tgz ghp\\docs\\ >NUL

pushd ghp
if exist docs\\index.yaml (
  helm repo index docs --merge docs\\index.yaml
) else (
  helm repo index docs
)
type NUL > docs\\.nojekyll

git add docs
git -c user.name="jenkins-ci" -c user.email="jenkins@example.com" commit -m "publish chart %GIT_SHA%" || ver >NUL
git push https://x-access-token:%GH_TOKEN%@github.com/azerez/devops0405-p3-Automation-CICD.git HEAD:gh-pages
popd

endlocal
'''
        }
      }
    }

    stage('Test (App quick checks)') {
      steps {
        bat """
docker run --rm -v "%CD%":/ws -w /ws/App python:3.11-slim sh -lc "pip install -r requirements.txt >/dev/null 2>&1 || true; if command -v pytest >/dev/null 2>&1 && (ls -1 test*.py 2>/dev/null || ls -1 tests/*.py 2>/dev/null) >/dev/null 2>&1; then pytest -q --junitxml=report.xml; else python -c 'print(\\\"no pytest or tests; basic check\\\")'; fi"
"""
      }
    }

    stage('Build & Push Docker') {
      when { expression { env.APP_CHANGED == '1' } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DOCKERHUB_USER', passwordVariable: 'DOCKERHUB_PASS')]) {
          bat """
docker login -u %DOCKERHUB_USER% -p %DOCKERHUB_PASS%
docker build -f App/Dockerfile -t ${DOCKER_IMAGE}:${env.GIT_SHA} App
docker push ${DOCKER_IMAGE}:${env.GIT_SHA}
"""
        }
      }
    }

    stage('Deploy to minikube') {
      when { allOf { branch 'main'; expression { env.APP_CHANGED == '1' || env.HELM_CHANGED == '1' } } }
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
          bat """
helm upgrade --install ${APP_NAME} ${CHART_DIR} ^
  --namespace ${K8S_NAMESPACE} ^
  --set image.repository=${DOCKER_IMAGE} ^
  --set image.tag=${env.GIT_SHA} ^
  --set image.pullPolicy=IfNotPresent
"""
        }
      }
    }

    stage('Smoke Test') {
      when { allOf { branch 'main'; expression { env.APP_CHANGED == '1' || env.HELM_CHANGED == '1' } } }
      steps {
        bat """
kubectl -n ${K8S_NAMESPACE} rollout status deploy/${APP_NAME} --timeout=180s ^
  || (kubectl -n ${K8S_NAMESPACE} get pods -o wide & exit /b 1)

set SVC=
for /f %%s in ('kubectl -n ${K8S_NAMESPACE} get svc -l app.kubernetes.io/instance=${APP_NAME} -o jsonpath^="{.items[0].metadata.name}"') do set SVC=%%s
if not defined SVC for /f %%s in ('kubectl -n ${K8S_NAMESPACE} get svc -l app.kubernetes.io/name=${APP_NAME} -o jsonpath^="{.items[0].metadata.name}"') do set SVC=%%s
if not defined SVC set SVC=${APP_NAME}

kubectl -n ${K8S_NAMESPACE} get svc %SVC% || (kubectl -n ${K8S_NAMESPACE} get svc & echo ERROR: service not found & exit /b 2)

for /f %%u in ('minikube service %SVC% --url -n ${K8S_NAMESPACE}') do set URL=%%u
curl -sSf %URL% > NUL
"""
      }
    }
  }

  post {
    success {
      junit allowEmptyResults: true, testResults: 'App/report.xml'
      archiveArtifacts artifacts: '.release/*.tgz', fingerprint: true, allowEmptyArchive: true
    }
    always {
      cleanWs()
    }
  }
}

