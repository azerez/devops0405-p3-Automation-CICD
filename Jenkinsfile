pipeline {
  agent any
  options { timestamps(); skipDefaultCheckout(false) }

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
          // ---------- Chart.yaml ----------
          def chartPath = "${CHART_DIR}/Chart.yaml"
          def lines = readFile(chartPath).readLines()
          boolean sawVersion = false
          boolean sawAppVersion = false

          for (int i = 0; i < lines.size(); i++) {
            def ln = lines[i]

            // version: X.Y.Z   -> bump Z
            if (ln ==~ /\s*version:\s*\d+\.\d+\.\d+(\s*#.*)?\s*$/) {
              def nums = (ln.findAll(/\d+/)).collect { it as int }
              if (nums.size() >= 3) {
                def bumped = "${nums[0]}.${nums[1]}.${nums[2] + 1}"
                lines[i] = ln.replaceFirst(/\d+\.\d+\.\d+/, bumped)
                sawVersion = true
              }
            }

            // appVersion: "<sha>"
            if (ln ==~ /\s*appVersion:.*/) {
              lines[i] = ln.replaceFirst(/(?m)^(\s*appVersion:\s*).*/, "\$1\"${env.GIT_SHA}\"")
              sawAppVersion = true
            }
          }

          if (!sawAppVersion) {
            lines << "appVersion: \"${env.GIT_SHA}\""
          }
          writeFile(file: chartPath, text: lines.join(System.lineSeparator()))

          // ---------- values.yaml ----------
          def valuesPath = "${CHART_DIR}/values.yaml"
          def vals = readFile(valuesPath)
          vals = vals.replaceFirst(/(?m)^(\s*repository:\s*).*/, "\$1${DOCKER_IMAGE}")
          vals = vals.replaceFirst(/(?m)^(\s*tag:\s*).*/, "\$1\"${env.GIT_SHA}\"")
          writeFile(file: valuesPath, text: vals)

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
REM keep the artifact before switching branches
if not exist _chart_out mkdir _chart_out
copy /Y .release\\*.tgz _chart_out\\ >NUL

git config --global credential.helper ""
git config --global user.name "jenkins-ci"
git config --global user.email "jenkins@example.com"

git fetch origin gh-pages 1>NUL 2>NUL || ver >NUL
git stash --include-untracked 1>NUL 2>NUL
git checkout -B gh-pages

if not exist docs mkdir docs
move /Y _chart_out\\*.tgz docs\\ >NUL
rmdir /S /Q _chart_out 2>NUL

if exist docs\\index.yaml (
  helm repo index docs --merge docs\\index.yaml
) else (
  helm repo index docs
)
type NUL > docs\\.nojekyll

set REMOTE=https://x-access-token:%GH_TOKEN%@github.com/azerez/devops0405-p3-Automation-CICD.git
git add docs
git commit -m "publish chart %GIT_SHA%" || ver >NUL
git push %REMOTE% HEAD:gh-pages --force
'''
        }
      }
    }

    stage('Build & Push Docker') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds',
                                          usernameVariable: 'DOCKERHUB_USER',
                                          passwordVariable: 'DOCKERHUB_PASS')]) {
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

  post { always { cleanWs() } }
}

