// ---------- Helpers ----------
@NonCPS
String bumpChartYaml(String text, String sha) {
  List<String> lines = (text.split(/\r?\n/, -1) as List<String>)

  // bump X.Y.Z -> X.Y.(Z+1)
  int verIdx = lines.findIndexOf { it ==~ /^\s*version:\s*\d+\.\d+\.\d+\s*$/ }
  if (verIdx >= 0) {
    def m = (lines[verIdx] =~ /(\d+)\.(\d+)\.(\d+)/)[0]
    int patch = (m[3] as int) + 1
    lines[verIdx] = ("version: ${m[1]}.${m[2]}.${patch}").toString()
  }

  // set appVersion (quoted)
  int appIdx = lines.findIndexOf { it ==~ /^\s*appVersion:\s*.*/ }
  if (appIdx >= 0) {
    lines[appIdx] = ("appVersion: \"${sha}\"").toString()
  } else {
    lines.add(("appVersion: \"${sha}\"").toString())
  }
  return lines.join('\n') + '\n'
}

@NonCPS
String bumpValuesTag(String text, String sha) {
  List<String> lines = (text.split(/\r?\n/, -1) as List<String>)
  int tagIdx = lines.findIndexOf { it ==~ /^\s*tag:\s*.*/ }
  if (tagIdx >= 0) {
    lines[tagIdx] = ('  tag: "' + sha + '"') as String
  } else {
    int imageIdx = lines.findIndexOf { it ==~ /^\s*image:\s*$/ }
    if (imageIdx >= 0) {
      lines.add(imageIdx + 1, ('  tag: "' + sha + '"') as String)
    } else {
      lines.add(('tag: "' + sha + '"') as String)
    }
  }
  return lines.join('\n') + '\n'
}

// ---------------------- Pipeline ----------------------
pipeline {
  agent any
  options { timestamps(); skipDefaultCheckout(true) }

  environment {
    CHART_DIR    = 'helm/flaskapp'
    RELEASE_DIR  = '.release'
    DOCKER_IMAGE = 'erezazu/devops0405-docker-flask-app'
  }

  stages {
    stage('Checkout SCM') { steps { checkout scm } }

    stage('Init (capture SHA)') {
      steps {
        script {
          // Return ONLY the SHA (no שורת פקודה)
          env.GIT_SHA = powershell(returnStdout: true, script: '(git rev-parse --short HEAD).Trim()').trim()
          echo "GIT_SHA = ${env.GIT_SHA}"
        }
      }
    }

    stage('Helm Lint') {
      steps { powershell 'helm lint ${env:CHART_DIR}' }
    }

    stage('Bump Chart Version (patch)') {
      steps {
        script {
          def chartPath  = "${env.CHART_DIR}/Chart.yaml"
          def valuesPath = "${env.CHART_DIR}/values.yaml"

          def chartTxt   = readFile(chartPath)
          def valuesTxt  = readFile(valuesPath)

          def newChart   = bumpChartYaml(chartTxt,  env.GIT_SHA)
          def newValues  = bumpValuesTag(valuesTxt, env.GIT_SHA)

          writeFile(file: chartPath,  text: newChart)
          writeFile(file: valuesPath, text: newValues)

          echo "Chart and values updated for ${env.GIT_SHA}"
        }
      }
    }

    stage('Package Chart') {
      steps {
        powershell """
          New-Item -ItemType Directory -Force -Path '${env:RELEASE_DIR}' | Out-Null
          helm package '${env:CHART_DIR}' -d '${env:RELEASE_DIR}'
        """
      }
    }

    stage('Publish to gh-pages') {
      steps {
        withCredentials([string(credentialsId: 'GHTOKEN', variable: 'GHTOKEN')]) {
          script {
            env.REMOTE_URL = "https://${GHTOKEN}@github.com/azerez/devops0405-p3-Automation-CICD.git"
          }
          bat '''
            if exist ghp ( rmdir /s /q ghp )
            git worktree prune
            git fetch origin gh-pages
            git worktree add ghp gh-pages
          '''
          powershell '''
            $pkg = Get-ChildItem -Path "${env:RELEASE_DIR}" -Filter "*.tgz" | Select-Object -First 1
            New-Item -ItemType Directory -Force -Path "ghp/docs" | Out-Null
            Copy-Item $pkg.FullName -Destination "ghp/docs/"
            if (Test-Path "ghp/docs/.nojekyll") { } else { Set-Content -Path "ghp/docs/.nojekyll" -Value "" -NoNewline }
            if (Test-Path "ghp/docs/index.yaml") {
              helm repo index "ghp/docs" --merge "ghp/docs/index.yaml"
            } else {
              helm repo index "ghp/docs"
            }
          '''
          bat '''
            cd ghp
            git config user.email "ci@example.com"
            git config user.name  "jenkins-ci"
            git add docs
            git commit -m "publish chart flaskapp %GIT_SHA%" || echo Nothing to commit
            git push %REMOTE_URL% HEAD:gh-pages
          '''
        }
      }
    }

    stage('Build & Push Docker') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'DOCKERHUB',
                                          usernameVariable: 'DOCKER_USER',
                                          passwordVariable: 'DOCKER_PASS')]) {
          powershell """
            docker login -u $env:DOCKER_USER -p $env:DOCKER_PASS
            docker build -t ${env:DOCKER_IMAGE}:${env:GIT_SHA} -t ${env:DOCKER_IMAGE}:latest App
            docker push  ${env:DOCKER_IMAGE}:${env:GIT_SHA}
            docker push  ${env:DOCKER_IMAGE}:latest
          """
        }
      }
    }

    stage('Deploy to minikube') {
      steps {
        powershell """
          helm upgrade --install flaskapp '${env:CHART_DIR}' `
            --set image.repository='${env:DOCKER_IMAGE}' `
            --set image.tag='${env:GIT_SHA}' `
            --namespace default --create-namespace
        """
      }
    }
  }

  post { always { cleanWs() } }
}

