pipeline {
  agent any

  environment {
    // --- App/Helm/GitHub ---
    APP_NAME      = 'flaskapp'
    HELM_DIR      = 'helm/flaskapp'
    PAGES_DIR     = 'docs'
    HELM_REPO_URL = 'https://azerez.github.io/devops0405-p3-Automation-CICD'  // בלי /docs
    REPO_SLUG     = 'azerez/devops0405-p3-Automation-CICD'
    GIT_NAME      = 'jenkins-ci'
    GIT_EMAIL     = 'ci@example.local'

    // --- Docker image (חייב להיות זהה לערך ב-values.yaml) ---
    DOCKER_IMAGE  = 'erezazu/devops0405-docker-flask-app'
  }

  options { timestamps() }

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
        powershell "helm lint ${env.HELM_DIR}"
      }
    }

    stage('Bump Chart Version (patch)') {
      when { changeset pattern: 'helm/**', comparator: 'ANT' }
      steps {
        script {
          // bump version: x.y.(z+1)
          def chartPath = "${HELM_DIR}/Chart.yaml"
          def chart = readFile(chartPath)
          def m = (chart =~ /(?m)^version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)/)
          if (!m.find()) { error "version: not found in ${chartPath}" }
          def major = m.group(1) as int
          def minor = m.group(2) as int
          def patch = (m.group(3) as int) + 1
          def newVer = "${major}.${minor}.${patch}"

          chart = chart.replaceFirst(/(?m)^version:\s*[0-9]+\.[0-9]+\.[0-9]+/, "version: ${newVer}")

          if (chart =~ /(?m)^appVersion:/) {
            chart = chart.replaceFirst(/(?m)^appVersion:\s*.*/, "appVersion: ${env.GIT_SHA}")
          } else {
            chart += "\nappVersion: ${env.GIT_SHA}\n"
          }
          writeFile file: chartPath, text: chart

          // optionally refresh values.yaml tag (pipeline ידרוס ב--set, אבל נחמד לסנכרן)
          def valsPath = "${HELM_DIR}/values.yaml"
          if (fileExists(valsPath)) {
            def vals = readFile(valsPath)
            if (vals =~ /(?m)^\s*tag:/) {
              vals = vals.replaceFirst(/(?m)^\s*tag:.*$/, "  tag: \"${env.GIT_SHA}\"")
              writeFile file: valsPath, text: vals
            }
          }
          echo "Bumped chart to ${newVer}; appVersion/tag -> ${env.GIT_SHA}"
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
          @echo off
          setlocal enabledelayedexpansion

          git config user.email "${GIT_EMAIL}"
          git config user.name  "${GIT_NAME}"

          rem fetch remote gh-pages and base on it (avoid non-fast-forward)
          git fetch origin gh-pages

          for /f %%A in ('git rev-parse --verify --quiet remotes/origin/gh-pages') do set HAS_GHPAGES=1

          if defined HAS_GHPAGES (
            echo Using remote origin/gh-pages as base
            git checkout -B gh-pages origin/gh-pages
            git pull --rebase origin gh-pages
          ) else (
            echo Creating orphan gh-pages
            git checkout --orphan gh-pages
            git rm -rf .
          )

          if not exist ${PAGES_DIR} mkdir ${PAGES_DIR}
          if not exist ${PAGES_DIR}\\.nojekyll echo.> ${PAGES_DIR}\\.nojekyll

          move /Y .release\\*.tgz ${PAGES_DIR}\\

          helm repo index ${PAGES_DIR} --url ${HELM_REPO_URL}

          git add ${PAGES_DIR}
          git commit -m "publish chart ${APP_NAME} ${GIT_SHA}" || echo Nothing to commit

          git push https://${GHTOKEN}@github.com/${REPO_SLUG}.git gh-pages

          git checkout - 1>nul 2>nul
          endlocal
          """
        }
      }
    }

    stage('Build & Push Docker') {
      when { changeset pattern: 'App/**', comparator: 'ANT' }
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds',
                                          usernameVariable: 'DOCKER_USER',
                                          passwordVariable: 'DOCKER_PASS')]) {
          bat """
          @echo off
          docker login -u %DOCKER_USER% -p %DOCKER_PASS%
          docker build -t %DOCKER_IMAGE%:%GIT_SHA% -f App/Dockerfile App
          docker push %DOCKER_IMAGE%:%GIT_SHA%
          """
        }
      }
    }

    stage('Deploy to minikube') {
      when { branch 'main' }
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG_FILE')]) {
          bat """
          @echo off
          set KUBECONFIG=%KUBECONFIG_FILE%
          kubectl config current-context

          helm repo add flaskapp ${HELM_REPO_URL} --force-update
          helm repo update

          helm upgrade --install %APP_NAME% flaskapp/%APP_NAME% ^
            --namespace default --create-namespace ^
            --set image.repository=%DOCKER_IMAGE% ^
            --set image.tag=%GIT_SHA%
          """
        }
      }
    }
  }
}

