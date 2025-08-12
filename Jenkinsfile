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
          // Windows 'bat' echoes the command line. Keep only the last non-empty line.
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

    stage('Bump Chart Version (patch)') {
      steps {
        script {
          // ---------- Chart.yaml ----------
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

          // appVersion -> GIT_SHA (add if missing)
          int aIdx = chartLines.findIndexOf { it.trim().toLowerCase().startsWith('appversion:') }
          if (aIdx >= 0) {
            chartLines[aIdx] = "appVersion: ${env.GIT_SHA}"
          } else {
            chartLines << "appVersion: ${env.GIT_SHA}"
          }

          writeFile file: chartPath, text: chartLines.join('\n')

          // ---------- values.yaml ----------
          def valuesPath = "${CHART_DIR}/values.yaml"
          def lines = readFile(valuesPath).split(/\r?\n/, -1) as List
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
              // left the image block (indentation reduced)
              if (trimmed && leadLen <= imageIndent) {
                // add missing keys before leaving
                if (!repoSet) {
                  def sp = ''; for (int i=0; i<imageIndent+2; i++) sp += ' '
                  out << sp + "repository: ${DOCKER_IMAGE}"
                }
                if (!tagSet) {
                  def sp = ''; for (int i=0; i<imageIndent+2; i++) sp += ' '
                  out << sp + "tag: \"${env.GIT_SHA}\""
                }
                inImage = false
                out << line
                return
              }

              if (trimmed.startsWith('repository:')) {
                def sp = ''; for (int i=0; i<imageIndent+2; i++) sp += ' '
                out << sp + "repository: ${DOCKER_IMAGE}"
                repoSet = true
                return
              }
              if (trimmed.startsWith('tag:')) {
                def sp = ''; for (int i=0; i<imageIndent+2; i++) sp += ' '
                out << sp + "tag: \"${env.GIT_SHA}\""
                tagSet = true
                return
              }

              out << line
              return
            }

            out << line
          }

          // file ended while still in image block
          if (inImage) {
            if (!repoSet) {
              def sp = ''; for (int i=0; i<imageIndent+2; i++) sp += ' '
              out << sp + "repository: ${DOCKER_IMAGE}"
            }
            if (!tagSet) {
              def sp = ''; for (int i=0; i<imageIndent+2; i++) sp += ' '
              out << sp + "tag: \"${env.GIT_SHA}\""
            }
          }

          writeFile file: valuesPath, text: out.join('\n')
          echo "Chart and values updated for ${env.GIT_SHA}"
        }
      }
    }

    stage('Package Chart') {
      steps { bat "helm package -d \"${RELEASE_DIR}\" \"${CHART_DIR}\"" }
    }

    stage('Publish to gh-pages') {
      when { branch 'main' }
      steps {
        withCredentials([string(credentialsId: 'github-token', variable: 'GH_TOKEN')]) {
          bat '''
if not exist _chart_out mkdir _chart_out
copy /Y .release\\*.tgz _chart_out\\ 1>NUL

git fetch origin gh-pages 1>NUL 2>NUL || ver >NUL
git stash --include-untracked 1>NUL 2>NUL
git checkout -B gh-pages

if not exist docs mkdir docs
move /Y _chart_out\\*.tgz docs\\ 1>NUL
rmdir /S /Q _chart_out 1>NUL

if exist docs\\index.yaml (
  helm repo index docs --merge docs\\index.yaml
) else (
  helm repo index docs
)

type NUL > docs\\.nojekyll

set REMOTE=https://x-access-token:%GH_TOKEN%@github.com/azerez/devops0405-p3-Automation-CICD.git
git add docs
git -c user.name="jenkins-ci" -c user.email="jenkins@example.com" commit -m "publish chart %GIT_SHA%" || ver >NUL
git push %REMOTE% HEAD:gh-pages --force
'''
        }
      }
    }

    stage('Build & Push Docker') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DOCKERHUB_USER', passwordVariable: 'DOCKERHUB_PASS')]) {
          bat """
docker login -u %DOCKERHUB_USER% -p %DOCKERHUB_PASS%
docker build -t ${DOCKER_IMAGE}:${env.GIT_SHA} .
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

