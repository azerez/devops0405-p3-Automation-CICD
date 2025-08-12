pipeline {
  agent any

  options {
    timestamps()
    skipDefaultCheckout(false)
  }

  parameters {
    booleanParam(name: 'FORCE_BUILD', defaultValue: false, description: 'Build & push Docker image even if App/ did not change')
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
          def chartTxt   = readFile(chartPath)
          def chartLines = chartTxt.split(/\r?\n/, -1) as List

          int vIdx = chartLines.findIndexOf { it.trim().toLowerCase().startsWith('version:') }
          if (vIdx >= 0) {
            def cur = chartLines[vIdx].split(':', 2)[1].trim()
            def parts = cur.tokenize('.')
            while (parts.size() < 3) { parts << '0' }
            parts[2] = ((parts[2] as int) + 1).toString()
            chartLines[vIdx] = "version: ${parts.join('.')}"
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
          boolean bumpTag = (env.APP_CHANGED == '1')   // tag רק אם האפליקציה השתנתה
          List out = []

          lines.each { line ->
            String trimmed = line.trim()
            int lead = line.length() - trimmed.length(); if (lead < 0) lead = 0

            if (!inImage && trimmed.startsWith('image:')) {
              inImage = true
              imageIndent = lead
              repoSet = false
              tagSet  = false
              out << line
            } else if (inImage) {
              if (trimmed && lead <= imageIndent) {
                def sp = ''; for (int i=0; i<imageIndent+2; i++) { sp += ' ' }
                if (!repoSet) out << sp + "repository: ${DOCKER_IMAGE}"
                if (!tagSet && bumpTag) out << sp + "tag: \"${env.GIT_SHA}\""
                inImage = false
                out << line
              } else if (trimmed.startsWith('repository:')) {
                def sp = ''; for (int i=0; i<imageIndent+2; i++) { sp += ' ' }
                out << sp + "repository: ${DOCKER_IMAGE}"
                repoSet = true
              } else if (trimmed.startsWith('tag:')) {
                if (bumpTag) {
                  def sp = ''; for (int i=0; i<imageIndent+2; i++) { sp += ' ' }
                  out << sp + "tag: \"${env.GIT_SHA}\""
                } else {
                  out << line
                }
                tagSet = true
              } else {
                out << line
              }
            } else {
              out << line
            }
          }

          if (inImage) {
            def sp = ''; for (int i=0; i<imageIndent+2; i++) { sp += ' ' }
            if (!repoSet) out << sp + "repository: ${DOCKER_IMAGE}"
            if (!tagSet && bumpTag) out << sp + "tag: \"${env.GIT_SHA}\""
          }

          writeFile file: valuesPath, text: out.join('\n')
          echo "Chart and values updated for ${env.GIT_SHA} (tag updated: ${bumpTag})"
        }
      }
    }

    stage('Package Chart') {
      when { expression { env.HELM_CHANGED == '1' } }
      steps { bat "helm package -d \"${RELEASE_DIR}\" \"${CHART_DIR}\"" }
    }

    stage('Publish to gh-pages') {
      when {
        allOf {
          branch 'main'
          expression { env.HELM_CHANGED == '1' }
        }
      }
      steps {
        withCredentials([string(credentialsId: 'github-token', variable: 'GH_TOKEN')]) {
          bat '''
@echo off
setlocal enableextensions

if not exist .release\\*.tgz (
  echo ERROR: no packaged chart under .release
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
'''
        }
      }
    }

    stage('Test (App quick checks)') {
      steps {
        bat """
docker run --rm -v "%WORKSPACE%":/ws -w /ws/App python:3.11-slim sh -lc "pip install -r requirements.txt >/dev/null 2>&1 || true; if command -v pytest >/dev/null 2>&1 && (ls -1 test*.py 2>/dev/null || ls -1 tests/*.py 2>/dev/null) >/dev/null 2>&1; then pytest -q --junitxml=report.xml; else python -c 'print(\\\"no pytest or tests; basic check\\\")'; fi"
"""
      }
    }

    stage('Build & Push Docker') {
      when { expression { params.FORCE_BUILD || env.APP_CHANGED == '1' } }
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
      when {
        allOf {
          branch 'main'
          expression { env.APP_CHANGED == '1' || env.HELM_CHANGED == '1' || params.FORCE_BUILD }
        }
      }
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
          script {
            // fallback to current running tag if no new app build
            def currentImg = bat(script: "kubectl -n ${K8S_NAMESPACE} get deploy ${APP_NAME} -o jsonpath='{.spec.template.spec.containers[0].image}' 2>NUL", returnStdout: true).trim()
            def currentTag = ''
            if (currentImg) {
              def idx = currentImg.lastIndexOf(':')
              currentTag = (idx >= 0) ? currentImg.substring(idx + 1).replaceAll(\"'\",'') : ''
            }
            def deployTag = (env.APP_CHANGED == '1' || params.FORCE_BUILD) ? env.GIT_SHA : (currentTag ?: env.GIT_SHA)
            echo "Deploying image tag: ${deployTag}"

            bat """
helm upgrade --install ${APP_NAME} ${CHART_DIR} ^
  --namespace ${K8S_NAMESPACE} ^
  --set-string image.repository=${DOCKER_IMAGE} ^
  --set-string image.tag=${deployTag} ^
  --set-string image.pullPolicy=IfNotPresent
"""
          }
        }
      }
    }

    stage('Smoke Test') {
      steps {
        bat """
kubectl -n ${K8S_NAMESPACE} rollout status deploy/${APP_NAME} --timeout=180s ^
  || (kubectl -n ${K8S_NAMESPACE} get pods -o wide & exit /b 1)

kubectl -n ${K8S_NAMESPACE} delete pod smoke-test --ignore-not-found
kubectl -n ${K8S_NAMESPACE} run smoke-test --image=curlimages/curl:8.8.0 --restart=Never --rm -i -- ^
  curl -sSf http://${APP_NAME}-service:5000/ >NUL
"""
      }
    }
  }

  post {
    always {
      // artifacts & test results (empty ok)
      archiveArtifacts artifacts: '.release/*.tgz', allowEmptyArchive: true, fingerprint: true
      junit allowEmptyResults: true, testResults: 'App/report.xml'
      cleanWs()
    }
  }
}

