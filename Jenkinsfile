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
          // Keep the last non-empty line from Windows bat output
          def out = bat(script: 'git rev-parse --short HEAD', returnStdout: true)
          def lines = out.readLines().collect { it?.trim() }.findAll { it }
          env.GIT_SHA = lines ? lines[-1] : 'unknown'
          echo "GIT_SHA = ${env.GIT_SHA}"
        }
      }
    }

    stage('Helm Lint') {
      steps {
        dir("${CHART_DIR}") { bat 'helm lint .' }
      }
    }

    // >>> The only addition: bump version/appVersion and ensure image tag <<<
    stage('Bump Chart Version (patch)') {
      steps {
        script {
          // ----- Chart.yaml -----
          def chartPath  = "${CHART_DIR}/Chart.yaml"
          def chartLines = readFile(chartPath).split(/\r?\n/, -1) as List

          // bump x.y.z -> x.y.(z+1)
          int vIdx = chartLines.findIndexOf { it?.trim()?.toLowerCase()?.startsWith('version:') }
          if (vIdx >= 0) {
            def cur   = chartLines[vIdx].split(':', 2)[1].trim()
            def parts = cur.tokenize('.')
            while (parts.size() < 3) { parts << '0' }
            parts[2] = ((parts[2] as int) + 1).toString()
            chartLines[vIdx] = "version: ${parts.join('.')}"
          } else {
            chartLines << "version: 0.1.0"
          }

          // set appVersion to the current short SHA (append if missing)
          int aIdx = chartLines.findIndexOf { it?.trim()?.toLowerCase()?.startsWith('appversion:') }
          if (aIdx >= 0) chartLines[aIdx] = "appVersion: ${env.GIT_SHA}"
          else           chartLines << "appVersion: ${env.GIT_SHA}"

          writeFile file: chartPath, text: chartLines.join('\n')

          // ----- values.yaml -----
          def valuesPath = "${CHART_DIR}/values.yaml"
          def lines = readFile(valuesPath).split(/\r?\n/, -1) as List

          boolean inImage = false
          int imageIndent = 0
          boolean repoSet = false
          boolean tagSet  = false
          List out = []

          lines.each { line ->
            String trimmed = (line ?: '').trim()
            int leadLen = line.length() - trimmed.length()
            if (leadLen < 0) leadLen = 0

            if (!inImage && trimmed.startsWith('image:')) {
              inImage = true; imageIndent = leadLen; repoSet = false; tagSet = false
              out << line; return
            }

            if (inImage) {
              if (trimmed && leadLen <= imageIndent) {
                def sp = ''.padLeft(imageIndent + 2, ' ' as char)
                if (!repoSet) out << sp + "repository: ${DOCKER_IMAGE}"
                if (!tagSet)  out << sp + "tag: \"${env.GIT_SHA}\""
                inImage = false
                out << line; return
              }
              if (trimmed.startsWith('repository:')) {
                def sp = ''.padLeft(imageIndent + 2, ' ' as char)
                out << sp + "repository: ${DOCKER_IMAGE}"; repoSet = true; return
              }
              if (trimmed.startsWith('tag:')) {
                def sp = ''.padLeft(imageIndent + 2, ' ' as char)
                out << sp + "tag: \"${env.GIT_SHA}\""; tagSet = true; return
              }
              out << line; return
            }

            out << line
          }

          if (inImage) {
            def sp = ''.padLeft(imageIndent + 2, ' ' as char)
            if (!repoSet) out << sp + "repository: ${DOCKER_IMAGE}"
            if (!tagSet)  out << sp + "tag: \"${env.GIT_SHA}\""
          }

          writeFile file: valuesPath, text: out.join('\n')
          echo "Chart and values updated for ${env.GIT_SHA}"
        }
      }
    }
    // <<< end bump >>>

    stage('Package Chart') {
      steps { bat "helm package -d \"${RELEASE_DIR}\" \"${CHART_DIR}\"" }
    }

    stage('Publish to gh-pages') {
      when { branch 'main' }
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

    stage('Build & Push Docker') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DOCKERHUB_USER', passwordVariable: 'DOCKERHUB_PASS')]) {
          bat """
echo %DOCKERHUB_PASS% | docker login -u %DOCKERHUB_USER% --password-stdin
docker build -f App/Dockerfile -t ${DOCKER_IMAGE}:${env.GIT_SHA} App
docker push ${DOCKER_IMAGE}:${env.GIT_SHA}
"""
        }
      }
    }

    stage('Deploy to minikube') {
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
  }

  post {
    always { cleanWs() }
  }
}

