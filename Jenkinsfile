pipeline {
  agent any

  environment {
    CHART_DIR   = 'helm/flaskapp'
    RELEASE_DIR = '.release'

    // GitHub repo + Pages URL
    GITHUB_REPO = 'https://github.com/azerez/devops0405-p3-Automation-CICD.git'
    PAGES_URL   = 'https://azerez.github.io/devops0405-p3-Automation-CICD'

    // Docker image
    DOCKER_IMAGE = 'erezazu/devops0405-docker-flask-app'
  }

  options {
    skipDefaultCheckout(true)
    timestamps()
  }

  stages {
    stage('Checkout SCM') {
      steps { checkout scm }
    }

    stage('Init (capture SHA)') {
      steps {
        script {
          env.GIT_SHA = bat(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
          echo "GIT_SHA = ${env.GIT_SHA}"
        }
      }
    }

    stage('Helm Lint') {
      steps {
        powershell 'helm lint ${env.CHART_DIR}'
      }
    }

    stage('Bump Chart Version (patch)') {
      steps {
        script {
          // Update appVersion
          def chart = readFile("${env.CHART_DIR}/Chart.yaml")
          chart = chart.replaceAll(/(?m)^appVersion:\s*.*/, "appVersion: ${env.GIT_SHA}")
          writeFile file: "${env.CHART_DIR}/Chart.yaml", text: chart

          // Bump patch version
          def m = (chart =~ /(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\s*$/)
          if (m.find()) {
            int maj = m.group(1) as int
            int min = m.group(2) as int
            int pat = (m.group(3) as int) + 1
            def newVer = "${maj}.${min}.${pat}"
            def c2 = readFile("${env.CHART_DIR}/Chart.yaml")
                       .replaceFirst(/(?m)^version:\s*\d+\.\d+\.\d+/, "version: ${newVer}")
            writeFile file: "${env.CHART_DIR}/Chart.yaml", text: c2
          }

          // Update values.yaml (repository + tag)
          def values = readFile("${env.CHART_DIR}/values.yaml")
          values = values
            .replaceAll(/(?m)^(\s*repository:\s*).*/, "\$1${env.DOCKER_IMAGE}")
            .replaceAll(/(?m)^(\s*tag:\s*).*/, "\$1\"${env.GIT_SHA}\"")
          writeFile file: "${env.CHART_DIR}/values.yaml", text: values
        }
      }
    }

    stage('Package Chart') {
      steps {
        powershell """
          if (!(Test-Path '${env.RELEASE_DIR}')) { New-Item -ItemType Directory -Path '${env.RELEASE_DIR}' | Out-Null }
          helm package '${env.CHART_DIR}' -d '${env.RELEASE_DIR}'
        """
      }
    }

    stage('Publish to gh-pages') {
      steps {
        withCredentials([string(credentialsId: 'github-token', variable: 'GHTOKEN')]) {
          bat """
            git fetch origin gh-pages 2>NUL  || ver >NUL
            git checkout -B gh-pages
            mkdir docs 2>NUL  || ver >NUL
            move /Y ${env.RELEASE_DIR}\\*.tgz docs\\
          """
          powershell """
            helm repo index docs --url ${env.PAGES_URL}
          """
          bat """
            git add docs
            git -c user.name="jenkins-ci" -c user.email="jenkins@example.com" commit -m "publish chart ${env.GIT_SHA}"  || ver >NUL
            git -c http.extraheader="AUTHORIZATION: bearer %GHTOKEN%" push ${env.GITHUB_REPO} HEAD:gh-pages --force
          """
        }
      }
    }

    stage('Build & Push Docker') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
          bat """
            docker build -t ${env.DOCKER_IMAGE}:${env.GIT_SHA} -t ${env.DOCKER_IMAGE}:latest App
            echo %DOCKER_PASS% | docker login -u %DOCKER_USER% --password-stdin
            docker push ${env.DOCKER_IMAGE}:${env.GIT_SHA}
            docker push ${env.DOCKER_IMAGE}:latest
          """
        }
      }
    }

    stage('Deploy to minikube') {
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
          bat "set KUBECONFIG=%KUBECONFIG% && kubectl version --client"
          powershell """
            helm upgrade --install flaskapp ${env.CHART_DIR} `
              --set image.repository=${env.DOCKER_IMAGE} `
              --set image.tag=${env.GIT_SHA} `
              --namespace default --create-namespace
          """
        }
      }
    }
  }

  post {
    always {
      // no stage here!
      cleanWs()
    }
  }
}

