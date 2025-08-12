pipeline {
  agent any

  options {
    timestamps()
    skipDefaultCheckout(true)
    disableConcurrentBuilds()
  }

  environment {
    CHART_DIR    = 'helm/flaskapp'
    RELEASE_DIR  = '.release'
    GH_PAGES_URL = 'https://azerez.github.io/devops0405-p3-Automation-CICD'

    IMAGE_REPO   = 'erezazu/devops0405-docker-flask-app'
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
      steps { dir(env.CHART_DIR) { powershell 'helm lint .' } }
    }

    stage('Bump Chart Version (patch)') {
      steps {
        script {
          def chartText = readFile("${env.CHART_DIR}/Chart.yaml")
          chartText = chartText.replaceAll(/(?m)^version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)/) { all, a,b,c -> "version: ${a}.${b}.${(c as int)+1}" }
          chartText = chartText.replaceAll(/(?m)^appVersion:\s*.*/, "appVersion: ${env.GIT_SHA}")
          writeFile file: "${env.CHART_DIR}/Chart.yaml", text: chartText

          def valuesText = readFile("${env.CHART_DIR}/values.yaml")
          valuesText = valuesText
            .replaceAll(/(?m)^(\s*repository:\s*).*/, "\$1${env.IMAGE_REPO}")
            .replaceAll(/(?m)^(\s*tag:\s*).*/, "\$1\"${env.GIT_SHA}\"")
          writeFile file: "${env.CHART_DIR}/values.yaml", text: valuesText
        }
      }
    }

    stage('Package Chart') {
      steps {
        powershell "if (!(Test-Path '${env.RELEASE_DIR}')) { New-Item -ItemType Directory -Path '${env.RELEASE_DIR}' | Out-Null }"
        dir(env.CHART_DIR) {
          powershell "helm package . -d '${env.WORKSPACE}\\\\${env.RELEASE_DIR}'"
        }
      }
    }

    stage('Publish to gh-pages') {
      steps {
        withCredentials([string(credentialsId: 'github-token', variable: 'GHTOKEN')]) {
          bat """
            git fetch origin gh-pages 2>NUL || ver 1>NUL
            git checkout -B gh-pages
            mkdir docs 2>NUL || ver 1>NUL
            move /Y %WORKSPACE%\\%RELEASE_DIR%\\*.tgz docs\\
          """
          // build/merge index.yaml WITHOUT $null
          powershell """
            if (Test-Path 'docs/index.yaml') {
              helm repo index 'docs' --url '${env.GH_PAGES_URL}' --merge 'docs/index.yaml'
            } else {
              helm repo index 'docs' --url '${env.GH_PAGES_URL}'
            }
          """
          bat '''
            git add docs
            git -c user.name="jenkins-ci" -c user.email="jenkins@example.com" commit -m "publish chart %GIT_SHA%" || ver 1>NUL
            git -c http.extraheader="AUTHORIZATION: bearer %GHTOKEN%" push https://github.com/azerez/devops0405-p3-Automation-CICD.git HEAD:gh-pages --force
          '''
        }
      }
    }

    stage('Build & Push Docker') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DOCKERHUB_USER', passwordVariable: 'DOCKERHUB_PASS')]) {
          powershell """
            docker login -u "$env:DOCKERHUB_USER" -p "$env:DOCKERHUB_PASS"
            docker build -t ${env.IMAGE_REPO}:${env.GIT_SHA} -t ${env.IMAGE_REPO}:latest App
            docker push ${env.IMAGE_REPO}:${env.GIT_SHA}
            docker push ${env.IMAGE_REPO}:latest
          """
        }
      }
    }

    stage('Deploy to minikube') {
      steps {
        withKubeConfig([credentialsId: 'kubeconfig']) {
          powershell """
            helm upgrade --install flaskapp ${env.CHART_DIR} `
              --namespace flaskapp --create-namespace `
              --set image.repository=${env.IMAGE_REPO} `
              --set image.tag=${env.GIT_SHA}
          """
        }
      }
    }
  }

  post { always { cleanWs() } }
}

