pipeline {
  agent any

  environment {
    APP_NAME      = 'flaskapp'
    HELM_DIR      = 'helm/flaskapp'
    PAGES_DIR     = 'docs'
    HELM_REPO_URL = 'https://azerez.github.io/devops0405-p3-Automation-CICD'
    REPO_SLUG     = 'azerez/devops0405-p3-Automation-CICD'

    // Docker image to build & deploy
    DOCKER_REPO   = 'erezazu/devops0405-docker-flask-app'

    GIT_NAME      = 'jenkins-ci'
    GIT_EMAIL     = 'ci@example.local'
  }

  options { timestamps() }

  /*
   * Pure-Groovy helpers (no Jenkins steps inside).
   * We avoid System.lineSeparator() to keep the sandbox happy.
   */
  @NonCPS
  String bumpChartYaml(String text, String sha) {
    // keep CRLF or LF by splitting on \r?\n, preserving empty trailing part
    def lines = text.split(/\r?\n/, -1)
    int verIdx = lines.findIndexOf { it ==~ /^\s*version:\s*\d+\.\d+\.\d+\s*$/ }
    if (verIdx >= 0) {
      def m = (lines[verIdx] =~ /(\d+)\.(\d+)\.(\d+)/)[0]
      int patch = (m[3] as int) + 1
      lines[verIdx] = "version: ${m[1]}.${m[2]}.${patch}"
    }
    int appIdx = lines.findIndexOf { it ==~ /^\s*appVersion:\s*.*/ }
    if (appIdx >= 0) {
      lines[appIdx] = "appVersion: ${sha}"
    } else {
      lines += "appVersion: ${sha}"
    }
    return lines.join('\n') + '\n'
  }

  @NonCPS
  String bumpValuesTag(String text, String sha) {
    def lines = text.split(/\r?\n/, -1)
    int idx = lines.findIndexOf { it ==~ /^\s*tag:\s*.*/ }
    if (idx >= 0) {
      lines[idx] = '  tag: "' + sha + '"'
    } else {
      // try to add under image: block; if not found, just append under root
      int imageIdx = lines.findIndexOf { it ==~ /^\s*image:\s*$/ }
      if (imageIdx >= 0) {
        lines.add(imageIdx + 1, '  tag: "' + sha + '"')
      } else {
        lines += 'tag: "' + sha + '"'
      }
    }
    return lines.join('\n') + '\n'
  }

  stages {

    stage('Checkout') {
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
      when { changeset pattern: 'helm/**', comparator: 'ANT' }
      steps {
        powershell 'helm lint ${env:HELM_DIR}'
      }
    }

    stage('Bump Chart Version (patch)') {
      when { changeset pattern: 'helm/**', comparator: 'ANT' }
      steps {
        script {
          // Chart.yaml
          def chartPath = "${env.HELM_DIR}/Chart.yaml"
          def chartText = readFile(chartPath)
          def newChart = bumpChartYaml(chartText, env.GIT_SHA)
          writeFile file: chartPath, text: newChart

          // values.yaml (image tag)
          def valuesPath = "${env.HELM_DIR}/values.yaml"
          if (fileExists(valuesPath)) {
            def valuesText = readFile(valuesPath)
            def newValues = bumpValuesTag(valuesText, env.GIT_SHA)
            writeFile file: valuesPath, text: newValues
          }

          echo "Bumped chart; appVersion/tag -> ${env.GIT_SHA}"
        }
      }
    }

    stage('Package Chart') {
      when { changeset pattern: 'helm/**', comparator: 'ANT' }
      steps {
        powershell '''
          $ErrorActionPreference = "Stop"
          if (Test-Path ".release") { Remove-Item -Recurse -Force ".release" }
          New-Item -ItemType Directory ".release" | Out-Null
          helm package ${env:HELM_DIR}
          Move-Item "${env:HELM_DIR}\\${env:APP_NAME}-*.tgz" ".release\\" -Force
        '''
      }
    }

    stage('Publish to gh-pages') {
      when { changeset pattern: 'helm/**', comparator: 'ANT' }
      steps {
        withCredentials([string(credentialsId: 'github-token', variable: 'GHTOKEN')]) {
          bat """
            git config user.email "${GIT_EMAIL}"
            git config user.name  "${GIT_NAME}"
            git fetch origin gh-pages 2>nul
            for /f %%i in ('git rev-parse --verify --quiet refs/remotes/origin/gh-pages') do set HASGHPAGES=1
            if not defined HASGHPAGES (
              git checkout --orphan gh-pages
              git rm -rf . 2>nul
            ) else (
              git checkout -B gh-pages origin/gh-pages
              git reset --hard origin/gh-pages
            )

            if not exist ${PAGES_DIR} mkdir ${PAGES_DIR}
            type nul > ${PAGES_DIR}\\.nojekyll
          """
          powershell '''
            $ErrorActionPreference = "Stop"
            Move-Item ".release\\*.tgz" "${env:PAGES_DIR}\\" -Force
            helm repo index "${env:PAGES_DIR}" --url ${env:HELM_REPO_URL}
          '''
          bat """
            git add ${PAGES_DIR}
            git commit -m "publish chart ${APP_NAME} ${GIT_SHA}" 2>nul || echo Nothing to commit
            git push "https://${GHTOKEN}@github.com/${REPO_SLUG}.git" gh-pages
            git checkout -f main
          """
        }
      }
    }

    stage('Build & Push Docker') {
      when { changeset pattern: 'App/**', comparator: 'ANT' }
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
          bat """
            docker build -t ${DOCKER_REPO}:${GIT_SHA} -t ${DOCKER_REPO}:latest App
            echo %DOCKER_PASS% | docker login --username %DOCKER_USER% --password-stdin
            docker push ${DOCKER_REPO}:${GIT_SHA}
            docker push ${DOCKER_REPO}:latest
            docker logout
          """
        }
      }
    }

    stage('Deploy to minikube') {
      when {
        allOf {
          changeset pattern: 'helm/**', comparator: 'ANT'
          expression { return env.GIT_SHA?.trim() }
        }
      }
      steps {
        powershell '''
          $ErrorActionPreference = "Stop"
          helm upgrade --install ${env:APP_NAME} ${env:HELM_DIR} `
            --namespace default --create-namespace `
            --set image.repository=${env:DOCKER_REPO} `
            --set image.tag=${env:GIT_SHA} `
            --wait
        '''
      }
    }
  }
}

