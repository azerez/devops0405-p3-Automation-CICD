/*
  Jenkinsfile — Windows agent (cmd/bat). English-only comments inside.

  Pipeline summary:
  - Checkout → Init (capture SHA)
  - Detect Helm changes: bump/package/publish ONLY if something under "helm/" changed
  - Helm lint
  - Test (quick app checks)
  - Build & Push Docker (tag = GIT_SHA)
  - Fetch kubeconfig from minikube dynamically (no static Jenkins creds)
  - K8s Preflight (prints cluster-info; gates Deploy/Smoke)
  - Deploy to minikube with Helm (image tag = GIT_SHA)
  - Smoke Test (/health)
  - Archive packaged charts (.tgz)
*/

pipeline {
  agent any

  options {
    timestamps()
    skipDefaultCheckout(false)
    disableConcurrentBuilds()
  }

  environment {
    APP_NAME      = 'flaskapp'
    CHART_DIR     = 'helm/flaskapp'
    RELEASE_DIR   = '.release'
    DOCKER_IMAGE  = 'erezazu/devops0405-docker-flask-app'
    K8S_NAMESPACE = 'default'
    K8S_OK        = 'false'   // set to true in Preflight if cluster reachable
  }

  stages {

    stage('Checkout SCM') {
      steps { checkout scm }
    }

    stage('Init (capture SHA)') {
      steps {
        script {
          // Keep last non-empty line (bat echoes the command)
          def out = bat(script: 'git rev-parse --short HEAD', returnStdout: true)
          def lines = out.readLines().collect { it?.trim() }.findAll { it }
          env.GIT_SHA = lines ? lines[-1] : 'unknown'
          echo "GIT_SHA = ${env.GIT_SHA}"
          env.BRANCH = env.BRANCH_NAME ?: 'main'
        }
      }
    }

    stage('Detect Helm Changes') {
      steps {
        script {
          bat label: 'compute diff', script: '''
@echo off
setlocal enabledelayedexpansion
git fetch origin %BRANCH% 1>NUL 2>NUL
for /f %%i in ('git rev-parse HEAD') do set HEAD=%%i
for /f %%i in ('git rev-parse --verify origin/%BRANCH% 2^>NUL') do set ORIG=%%i
if "!ORIG!"=="" (
  for /f %%i in ('git rev-parse HEAD~1 2^>NUL') do set BASE=%%i
) else (
  for /f %%i in ('git merge-base HEAD origin/%BRANCH%') do set BASE=%%i
)
git diff --name-only !BASE! !HEAD! > diff.txt
endlocal
'''
          def diff = fileExists('diff.txt') ? readFile('diff.txt') : ''
          echo "Changed files:\n${diff}"
          def changed = diff?.readLines()?.any { it.startsWith("${CHART_DIR}/") || it.startsWith('helm/') } ?: false
          env.HELM_CHANGED = changed ? 'true' : 'false'
          echo "HELM_CHANGED = ${env.HELM_CHANGED}"
        }
      }
    }

    stage('Helm Lint') {
      steps {
        dir("${CHART_DIR}") { bat 'helm lint .' }
      }
    }

    stage('Bump Chart Version (patch)') {
      when { expression { env.HELM_CHANGED == 'true' } }
      steps {
        script {
          // -------- Chart.yaml --------
          def chartPath  = "${CHART_DIR}/Chart.yaml"
          def chartTxt   = readFile(chartPath)
          def chartLines = chartTxt.split(/\r?\n/, -1) as List

          // bump version x.y.z -> x.y.(z+1)
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

          // appVersion -> SHA (append if missing)
          int aIdx = chartLines.findIndexOf { it.trim().toLowerCase().startsWith('appversion:') }
          if (aIdx >= 0) chartLines[aIdx] = "appVersion: ${env.GIT_SHA}"
          else chartLines << "appVersion: ${env.GIT_SHA}"

          writeFile file: chartPath, text: chartLines.join('\n')

          // -------- values.yaml --------
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
                if (!repoSet) out << "${sp}repository: ${DOCKER_IMAGE}"
                if (!tagSet)  out << "${sp}tag: \"${env.GIT_SHA}\""
                inImage = false
                out << line; return
              }
              if (trimmed.startsWith('repository:')) {
                out << (' ' * (imageIndent + 2)) + "repository: ${DOCKER_IMAGE}"; repoSet = true; return
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
            if (!repoSet) out << "${sp}repository: ${DOCKER_IMAGE}"
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
        bat "if not exist \"${RELEASE_DIR}\" mkdir \"${RELEASE_DIR}\""
        bat "helm package -d \"${RELEASE_DIR}\" \"${CHART_DIR}\""
        archiveArtifacts artifacts: "${RELEASE_DIR}/*.tgz", fingerprint: true
      }
    }

    stage('Publish to gh-pages') {
      when {
        allOf {
          branch 'main'
          expression { env.HELM_CHANGED == 'true' }
        }
      }
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
        bat '''
@echo off
where python >NUL 2>NUL || goto :eof
if exist requirements.txt (
  python -m pip install --no-cache-dir -r requirements.txt 1>NUL
)
if exist app.py  python -m py_compile app.py
if exist main.py python -m py_compile main.py
if exist tests (
  python -m pip install --no-cache-dir pytest 1>NUL
  pytest -q
)
'''
      }
    }

    stage('Build & Push Docker') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DOCKERHUB_USER', passwordVariable: 'DOCKERHUB_PASS')]) {
          bat '''
docker login -u %DOCKERHUB_USER% -p %DOCKERHUB_PASS%
docker build -f App/Dockerfile -t %DOCKER_IMAGE%:%GIT_SHA% App
docker push %DOCKER_IMAGE%:%GIT_SHA%
'''
        }
      }
    }

    stage('Fetch kubeconfig from minikube') {
      steps {
        bat '''
@echo off
REM Export a fresh kubeconfig from minikube into the workspace
minikube -p minikube kubectl -- config view --raw > kubeconfig
if errorlevel 1 (
  echo WARN: failed to export kubeconfig from minikube
)
'''
        script {
          env.KUBECONFIG = "${pwd()}\\kubeconfig"
          echo "KUBECONFIG set to ${env.KUBECONFIG}"
        }
      }
    }

    stage('K8s Preflight') {
      steps {
        script {
          def status = bat(returnStatus: true, script: '''
@echo off
kubectl config current-context
kubectl cluster-info
kubectl get nodes
''')
          env.K8S_OK = (status == 0) ? 'true' : 'false'
          echo "K8S_OK = ${env.K8S_OK}"
        }
      }
    }

    stage('Deploy to minikube') {
      when { expression { env.K8S_OK == 'true' } }
      steps {
        bat '''
helm upgrade --install %APP_NAME% %CHART_DIR% ^
  --namespace %K8S_NAMESPACE% --create-namespace ^
  --set image.repository=%DOCKER_IMAGE% ^
  --set image.tag=%GIT_SHA% ^
  --set image.pullPolicy=IfNotPresent
'''
      }
    }

    stage('Smoke Test') {
      when { expression { env.K8S_OK == 'true' } }
      steps {
        bat '''
@echo off
for /f "tokens=*" %%i in ('kubectl -n %K8S_NAMESPACE% rollout status deploy/%APP_NAME% --timeout=120s') do echo %%i
for /f "tokens=*" %%p in ('kubectl -n %K8S_NAMESPACE% get svc %APP_NAME% -o jsonpath="{.spec.ports[0].nodePort}"') do set NP=%%p
for /f "tokens=*" %%i in ('minikube ip') do set IP=%%i
curl -s http://%IP%:%NP%/health
'''
      }
    }
  }

  post {
    success { echo "OK: HELM_CHANGED=${env.HELM_CHANGED}, SHA=${env.GIT_SHA}, K8S_OK=${env.K8S_OK}" }
    always  { cleanWs() }
  }
}
a
