pipeline {
  agent any

  options {
    timestamps()
    skipDefaultCheckout(false)
  }

  environment {
    APP_NAME     = 'flaskapp'
    CHART_DIR    = 'helm/flaskapp'
    RELEASE_DIR  = '.release'
    DOCKER_IMAGE = 'erezazu/devops0405-docker-flask-app'
    K8S_NAMESPACE = 'default'
  }

  stages {

    stage('Checkout SCM') {
      steps {
        checkout scm
      }
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
        dir("${CHART_DIR}") {
          bat 'helm lint .'
        }
      }
    }

    stage('Bump Chart Version (patch)') {
      steps {
        script {
          // ---- Chart.yaml ----
          def chartPath = "${CHART_DIR}/Chart.yaml"
          def chartText = readFile(chartPath)
          def chartLines = chartText.readLines()
          def newLines = []
          String curVersion = null
          chartLines.each { line ->
            def t = line.trim()
            if (t.startsWith('version:')) {
              def v = t.substring('version:'.length()).trim()
              curVersion = v
              def parts = v.split('\\.')
              if (parts.size() >= 3) {
                parts[2] = ((parts[2] as int) + 1).toString()
              }
              def bumped = parts.join('.')
              newLines << "version: ${bumped}"
            } else if (t.startsWith('appVersion:')) {
              newLines << "appVersion: ${env.GIT_SHA}"
            } else {
              newLines << line
            }
          }
          writeFile(file: chartPath, text: newLines.join('\n'))

          // ---- values.yaml ----
          def valuesPath = "${CHART_DIR}/values.yaml"
          def valuesText = readFile(valuesPath)
          def vLines = valuesText.readLines()
          def out = []
          boolean inImage = false
          vLines.each { line ->
            def raw = line
            def s = raw.trim()
            if (s.startsWith('image:')) {
              inImage = true
              out << raw
              return
            }
            if (inImage && s.startsWith('repository:')) {
              out << raw.replaceFirst(/repository:.*/, "repository: ${DOCKER_IMAGE}")
              return
            }
            if (inImage && s.startsWith('tag:')) {
              out << raw.replaceFirst(/tag:.*/, "tag: \"${env.GIT_SHA}\"")
              return
            }
            if (inImage && (s == '' || s.startsWith('#') || (!s.startsWith('repository:') && !s.startsWith('tag:') && !s.startsWith('pullPolicy:') && !s.startsWith('-') && !s.startsWith(' ')))) {
              // left image block – naive but effective
              inImage = false
            }
            out << raw
          }
          writeFile(file: valuesPath, text: out.join('\n'))
          echo "Chart and values updated for ${env.GIT_SHA}"
        }
      }
    }

    stage('Package Chart') {
      steps {
        bat "helm package -d \"${RELEASE_DIR}\" \"${CHART_DIR}\""
      }
    }

    stage('Publish to gh-pages') {
      when { branch 'main' }
      steps {
        withCredentials([string(credentialsId: 'github-token', variable: 'GH_TOKEN')]) {
          bat '''
REM keep packaged chart before switching branches
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
    always {
      cleanWs()
    }
  }
}

