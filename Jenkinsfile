pipeline {
  agent any

  environment {
    CHART_DIR    = 'helm/flaskapp'
    RELEASE_DIR  = '.release'
    DOCKER_IMAGE = 'erezazu/devops0405-docker-flask-app'
  }

  options { timestamps() }

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
        powershell "helm lint ${env.CHART_DIR}"
      }
    }

    stage('Bump Chart Version (patch)') {
      steps {
        script {
          // Chart.yaml
          def chartPath = "${env.CHART_DIR}/Chart.yaml"
          def chartTxt  = readFile(chartPath)
          def verLine   = chartTxt.readLines().find { it.trim().startsWith('version:') } ?: 'version: 0.1.0'
          def ver       = verLine.split(':')[1].trim()
          def parts     = ver.tokenize('.')
          def newVer    = "${parts[0]}.${parts[1]}.${(parts[2] as int) + 1}"
          def newChart  = chartTxt.readLines().collect { ln ->
            if (ln.trim().startsWith('version:'))        "version: ${newVer}"
            else if (ln.trim().startsWith('appVersion:')) "appVersion: ${env.GIT_SHA}"
            else ln
          }.join('\n')
          writeFile file: chartPath, text: newChart

          // values.yaml
          def valuesPath = "${env.CHART_DIR}/values.yaml"
          def valuesTxt  = readFile(valuesPath)
          def newValues  = valuesTxt.readLines().collect { ln ->
            if (ln.trim().startsWith('repository:'))  "  repository: ${env.DOCKER_IMAGE}"
            else if (ln.trim().startsWith('tag:'))     "  tag: \"${env.GIT_SHA}\""
            else ln
          }.join('\n')
          writeFile file: valuesPath, text: newValues

          echo "Chart and values updated for ${env.GIT_SHA}"
        }
      }
    }

    stage('Package Chart') {
      steps {
        powershell """
          if (-not (Test-Path ${env.RELEASE_DIR})) { New-Item -ItemType Directory -Path ${env.RELEASE_DIR} | Out-Null }
          helm package ${env.CHART_DIR} -d ${env.RELEASE_DIR}
        """
      }
    }

    stage('Publish to gh-pages') {
      steps {
        withCredentials([string(credentialsId: 'github-token', variable: 'GHTOKEN')]) {
          // prepare gh-pages branch + docs
          bat """
            git fetch origin gh-pages 2>NUL  || ver 1>NUL
            git checkout -B gh-pages
            if not exist docs mkdir docs
            move /Y ${env.RELEASE_DIR}\\*.tgz docs\\
          """
          // build/merge index.yaml
          powershell '''
            if (Test-Path docs/index.yaml) {
              helm repo index docs --url https://azerez.github.io/devops0405-p3-Automation-CICD --merge docs/index.yaml
            } else {
              helm repo index docs --url https://azerez.github.io/devops0405-p3-Automation-CICD
            }
            git add docs
            git -c user.name="jenkins-ci" -c user.email="jenkins@example.com" commit -m "publish chart $env:GIT_SHA" 2>$null | Out-Null

            # disable any interactive auth from Git Credential Manager
            $env:GIT_TERMINAL_PROMPT = "0"
            $env:GCM_INTERACTIVE     = "Never"

            # build Basic auth header from username:PAT
            $pair = [Text.Encoding]::ASCII.GetBytes("azerez:$env:GHTOKEN")
            $b64  = [Convert]::ToBase64String($pair)

            git -c credential.helper= -c http.extraheader="Authorization: Basic $b64" `
                push https://github.com/azerez/devops0405-p3-Automation-CICD.git HEAD:gh-pages --force
          '''
        }
      }
    }

    stage('Build & Push Docker') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
          bat """
            docker login -u %DH_USER% -p %DH_PASS%
            docker build -t ${env.DOCKER_IMAGE}:${env.GIT_SHA} -t ${env.DOCKER_IMAGE}:latest App
            docker push ${env.DOCKER_IMAGE}:${env.GIT_SHA}
            docker push ${env.DOCKER_IMAGE}:latest
          """
        }
      }
    }

    stage('Deploy to minikube') {
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KCFG')]) {
          bat """
            set KUBECONFIG=%KCFG%
            helm upgrade --install flaskapp ${env.CHART_DIR} --namespace default --create-namespace ^
              --set image.repository=${env.DOCKER_IMAGE} --set image.tag=${env.GIT_SHA}
          """
        }
      }
    }
  }

  post {
    always {
      stage('Declarative: Post Actions') {
        cleanWs()
      }
    }
  }
}

