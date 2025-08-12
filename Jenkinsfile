pipeline {
  agent any
  options {
    timestamps()
    ansiColor('xterm')
  }

  environment {
    CHART_DIR   = 'helm/flaskapp'
    RELEASE_DIR = '.release'
    DOCS_DIR    = 'docs'
    IMAGE_REPO  = 'erezazu/devops0405-docker-flask-app'
    GIT_URL     = 'https://github.com/azerez/devops0405-p3-Automation-CICD.git'
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
        dir("${env.CHART_DIR}") {
          powershell 'helm lint .'
        }
      }
    }

    stage('Bump Chart Version (patch)') {
      steps {
        script {
          final String chartPath  = "${env.CHART_DIR}/Chart.yaml"
          final String valuesPath = "${env.CHART_DIR}/values.yaml"

          // --- Chart.yaml ---
          def chartText = readFile(chartPath)

          // Safe bump: find "version: A.B.C" and increase C. If not found, just warn.
          def m = (chartText =~ /(?m)^version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)/)
          if (m.find()) {
            int major = m.group(1) as int
            int minor = m.group(2) as int
            int patch = m.group(3) as int
            def newVersion = "${major}.${minor}.${patch + 1}"
            chartText = chartText.replaceFirst(
              /(?m)^version:\s*[0-9]+\.[0-9]+\.[0-9]+/,
              "version: ${newVersion}"
            )
            echo "Chart version bumped to ${newVersion}"
          } else {
            echo "WARN: 'version:' not found in Chart.yaml – leaving it unchanged"
          }

          // Ensure appVersion equals current GIT_SHA
          if ((chartText =~ /(?m)^appVersion:/).find()) {
            chartText = chartText.replaceFirst(/(?m)^appVersion:\s*.*/, "appVersion: ${env.GIT_SHA}")
          } else {
            chartText += "\nappVersion: ${env.GIT_SHA}\n"
          }
          writeFile(file: chartPath, text: chartText)

          // --- values.yaml ---
          def valuesText = readFile(valuesPath)
          valuesText = valuesText
            .replaceFirst(/(?m)^(\s*repository:\s*).*/, "\$1${env.IMAGE_REPO}")
            .replaceFirst(/(?m)^(\s*tag:\s*).*/,        "\$1\"${env.GIT_SHA}\"")
          writeFile(file: valuesPath, text: valuesText)

          echo "Chart and values updated for ${env.GIT_SHA}"
        }
      }
    }

    stage('Package Chart') {
      steps {
        powershell "helm package -d '${env.RELEASE_DIR}' '${env.CHART_DIR}'"
      }
    }

    stage('Publish to gh-pages') {
      steps {
        withCredentials([string(credentialsId: 'github-token', variable: 'GH_TOKEN')]) {
          // prepare gh-pages branch and files
          bat '''
git fetch origin gh-pages 1>NUL 2>NUL || ver >NUL
git add -A
git stash --include-untracked
git checkout -B gh-pages
if not exist docs mkdir docs
move /Y .release\\*.tgz docs\\
'''
          // (re)create index.yaml and .nojekyll
          powershell '''
if (Test-Path "docs/index.yaml") {
  helm repo index "docs" --merge "docs/index.yaml"
} else {
  helm repo index "docs"
}
New-Item -ItemType File -Path "docs/.nojekyll" -Force | Out-Null
'''
          // commit & push using token
          bat """
git add docs
git -c user.name="jenkins-ci" -c user.email="jenkins@example.com" commit -m "publish chart %GIT_SHA%" || ver >NUL
git -c http.extraheader="AUTHORIZATION: bearer %GH_TOKEN%" push ${env.GIT_URL} HEAD:gh-pages --force
"""
        }
      }
    }

    stage('Build & Push Docker') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
          bat """
docker login -u %DH_USER% -p %DH_PASS%
docker build -t %IMAGE_REPO%:%GIT_SHA% -f App\\Dockerfile .
docker push %IMAGE_REPO%:%GIT_SHA%
"""
        }
      }
    }

    stage('Deploy to minikube') {
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KCFG')]) {
          withEnv(["KUBECONFIG=${KCFG}"]) {
            powershell """
helm upgrade --install flaskapp ${env.CHART_DIR} `
  --values ${env.CHART_DIR}/values.yaml `
  --set image.repository=${env.IMAGE_REPO} `
  --set image.tag=${env.GIT_SHA}
"""
          }
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

