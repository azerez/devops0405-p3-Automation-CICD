pipeline {
  agent any

  options { timestamps() }

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
          // Capture only the last line (the SHA), then strip any non-hex chars
          def out = bat(script: 'git rev-parse --short HEAD', returnStdout: true)
          def lines = out.readLines()
          env.GIT_SHA = lines ? lines[-1].trim() : ''
          env.GIT_SHA = env.GIT_SHA.replaceAll('[^0-9a-fA-F]', '')
          echo "GIT_SHA = ${env.GIT_SHA}"
        }
      }
    }

    stage('Helm Lint') {
      steps {
        dir("${env.CHART_DIR}") {
          bat 'helm lint .'
        }
      }
    }

    stage('Bump Chart Version (patch)') {
      steps {
        script {
          final String chartPath  = "${env.CHART_DIR}/Chart.yaml"
          final String valuesPath = "${env.CHART_DIR}/values.yaml"

          // --- Chart.yaml bump ---
          String chartText = readFile(chartPath)
          List<String> lines = chartText.readLines()
          boolean bumped = false

          for (int i = 0; i < lines.size(); i++) {
            def m = (lines[i] =~ /^\s*version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)/)
            if (m.find()) {
              int major = m.group(1).toInteger()
              int minor = m.group(2).toInteger()
              int patch = m.group(3).toInteger()
              lines[i] = "version: ${major}.${minor}.${patch + 1}".toString()
              bumped = true
              break
            }
          }
          if (!bumped) { lines << "version: 0.1.0" }

          boolean appSet = false
          for (int i = 0; i < lines.size(); i++) {
            if ((lines[i] =~ /^\s*appVersion:/).find()) {
              lines[i] = "appVersion: \"${env.GIT_SHA}\"".toString()
              appSet = true
              break
            }
          }
          if (!appSet) { lines << "appVersion: \"${env.GIT_SHA}\"".toString() }

          writeFile(file: chartPath, text: lines.join('\n'))

          // --- values.yaml ensure repo+tag ---
          String valuesText = readFile(valuesPath)

          def hasRepo  = (valuesText =~ /(?m)^\s*repository:/).find()
          def hasTag   = (valuesText =~ /(?m)^\s*tag:/).find()
          def hasImage = (valuesText =~ /(?m)^\s*image:\s*$/).find() || valuesText.contains("\nimage:")

          if (hasRepo) {
            valuesText = valuesText.replaceFirst(/(?m)^\s*repository:\s*.*/, "  repository: ${env.IMAGE_REPO}")
          }
          if (hasTag) {
            valuesText = valuesText.replaceFirst(/(?m)^\s*tag:\s*.*/, "  tag: \"${env.GIT_SHA}\"")
          }

          if (!hasRepo || !hasTag) {
            String extra = ''
            if (!hasImage) extra += "image:\n"
            if (!hasRepo) extra += "  repository: ${env.IMAGE_REPO}\n"
            if (!valuesText.contains('pullPolicy:')) extra += "  pullPolicy: IfNotPresent\n"
            if (!hasTag)  extra += "  tag: \"${env.GIT_SHA}\"\n"
            valuesText += (valuesText.endsWith('\n') ? '' : '\n') + extra
          }

          writeFile(file: valuesPath, text: valuesText)

          echo "Chart and values updated for ${env.GIT_SHA}"
        }
      }
    }

    stage('Package Chart') {
      steps {
        bat 'helm package -d "%RELEASE_DIR%" "%CHART_DIR%"'
      }
    }

    stage('Publish to gh-pages') {
      when { branch 'main' }
      steps {
        withCredentials([string(credentialsId: 'github-token', variable: 'GH_TOKEN')]) {
          bat '''
git fetch origin gh-pages 1>NUL 2>NUL || ver >NUL
git add -A
git stash --include-untracked 1>NUL 2>NUL
git checkout -B gh-pages

if not exist docs mkdir docs
move /Y .release\\*.tgz docs\\

if exist docs\\index.yaml (
  helm repo index docs --merge docs\\index.yaml
) else (
  helm repo index docs
)

type NUL > docs\\.nojekyll

git add docs
git -c user.name="jenkins-ci" -c user.email="jenkins@example.com" commit -m "publish chart %GIT_SHA%" || ver >NUL
git -c http.extraheader="AUTHORIZATION: bearer %GH_TOKEN%" push %GIT_URL% HEAD:gh-pages --force
'''
        }
      }
    }

    stage('Build & Push Docker') {
      when { branch 'main' }
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
          bat '''
docker login -u %DH_USER% -p %DH_PASS%
docker build -t %IMAGE_REPO%:%GIT_SHA% -f App\\Dockerfile .
docker push %IMAGE_REPO%:%GIT_SHA%
'''
        }
      }
    }

    stage('Deploy to minikube') {
      when { branch 'main' }
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KCFG')]) {
          bat '''
set KUBECONFIG=%KCFG%
helm upgrade --install flaskapp %CHART_DIR% --values %CHART_DIR%\\values.yaml --set image.repository=%IMAGE_REPO% --set image.tag=%GIT_SHA%
'''
        }
      }
    }
  }

  post {
    always { cleanWs() }
  }
}

