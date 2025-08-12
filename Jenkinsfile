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
          env.GIT_SHA = bat(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
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
          // -------- Chart.yaml --------
          def chartPath = "${CHART_DIR}/Chart.yaml"
          def chartTxt  = readFile(chartPath)

          // bump version x.y.z -> x.y.(z+1)
          def m = (chartTxt =~ /(?m)^\s*version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)/)
          if (m.find()) {
            int x = m.group(1) as int
            int y = m.group(2) as int
            int z = (m.group(3) as int) + 1
            def newVer = "${x}.${y}.${z}"
            chartTxt = chartTxt.replaceFirst(/(?m)^\s*version:\s*[^\r\n]+/, "version: ${newVer}")
          } else {
            echo "WARN: version not found in Chart.yaml – leaving as-is"
          }

          // set appVersion to current SHA (add if missing)
          if ((chartTxt =~ /(?m)^\s*appVersion:\s*/).find()) {
            chartTxt = chartTxt.replaceFirst(/(?m)^\s*appVersion:\s*[^\r\n]*/, "appVersion: ${env.GIT_SHA}")
          } else {
            chartTxt = chartTxt + System.lineSeparator() + "appVersion: ${env.GIT_SHA}" + System.lineSeparator()
          }
          writeFile file: chartPath, text: chartTxt

          // -------- values.yaml --------
          def valuesPath = "${CHART_DIR}/values.yaml"
          def lines = readFile(valuesPath).split(/\r?\n/, -1) as List
          boolean inImage = false
          int imageIndent = 0
          boolean repoSet = false
          boolean tagSet  = false

          List out = []
          lines.each { line ->
            def leading = (line =~ /^\s*/)[0]
            def trimmed = line.trim()

            if (!inImage && trimmed ==~ /^image\s*:\s*(#.*)?$/) {
              inImage = true
              imageIndent = leading.size()
              repoSet = false
              tagSet  = false
              out << line
              return
            }

            if (inImage) {
              if (trimmed && leading.size() <= imageIndent) {
                // Leaving image block – add missing keys just before leaving
                if (!repoSet) out << (" " * (imageIndent + 2)) + "repository: ${DOCKER_IMAGE}"
                if (!tagSet)  out << (" " * (imageIndent + 2)) + "tag: \"${env.GIT_SHA}\""
                inImage = false
                // fall-through for current line outside image
              } else {
                if (trimmed ==~ /^repository\s*:.*/) {
                  out << (" " * (imageIndent + 2)) + "repository: ${DOCKER_IMAGE}"
                  repoSet = true
                  return
                }
                if (trimmed ==~ /^tag\s*:.*/) {
                  out << (" " * (imageIndent + 2)) + "tag: \"${env.GIT_SHA}\""
                  tagSet = true
                  return
                }
                out << line
                return
              }
            }

            out << line
          }
          // If file ended while still in image block, append missing keys
          if (inImage) {
            if (!repoSet) out << (" " * (imageIndent + 2)) + "repository: ${DOCKER_IMAGE}"
            if (!tagSet)  out << (" " * (imageIndent + 2)) + "tag: \"${env.GIT_SHA}\""
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

