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
          // ---- Chart.yaml (safe YAML) ----
          def chartPath = "${CHART_DIR}/Chart.yaml"
          def chart = readYaml file: chartPath

          // bump patch (x.y.z -> x.y.(z+1))
          def parts = chart.version.toString().tokenize('.')
          while (parts.size() < 3) { parts << '0' }
          parts[2] = ((parts[2] as int) + 1).toString()
          chart.version = parts.join('.')

          chart.appVersion = env.GIT_SHA
          writeYaml file: chartPath, data: chart

          // ---- values.yaml (safe YAML) ----
          def valuesPath = "${CHART_DIR}/values.yaml"
          def values = readYaml file: valuesPath

          if (!values.image) { values.image = [:] }
          values.image.repository = DOCKER_IMAGE
          values.image.tag = env.GIT_SHA
          values.image.pullPolicy = values.image.pullPolicy ?: 'IfNotPresent'

          writeYaml file: valuesPath, data: values

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

