// ---------- helpers (avoid CPS serialization problems) ----------
@NonCPS
String bumpChartYaml(String chart, String sha) {
  def m = (chart =~ /(?m)^\s*version:\s*(\d+)\.(\d+)\.(\d+)\s*$/)
  if (!m.find()) { throw new RuntimeException("version: not found in Chart.yaml") }
  int major = m.group(1) as int
  int minor = m.group(2) as int
  int patch = (m.group(3) as int) + 1
  String newVer = "${major}.${minor}.${patch}"

  // set new version
  chart = chart.replaceFirst(/(?m)^\s*version:\s*\d+\.\d+\.\d+\s*$/, "version: ${newVer}")

  // set/append appVersion to current git sha
  if ((chart =~ /(?m)^\s*appVersion:/).find()) {
    chart = chart.replaceFirst(/(?m)^\s*appVersion:\s*.*$/, "appVersion: ${sha}")
  } else {
    chart += "\nappVersion: ${sha}\n"
  }
  return chart
}

@NonCPS
String setTagInValues(String values, String sha) {
  if ((values =~ /(?m)^\s*tag:\s*/).find()) {
    return values.replaceFirst(/(?m)^\s*tag:\s*.*$/, "  tag: \"${sha}\"")
  }
  return values
}

// --------------------------- pipeline ---------------------------
pipeline {
  agent any

  environment {
    APP_NAME       = 'flaskapp'
    HELM_DIR       = 'helm/flaskapp'
    PAGES_DIR      = 'docs'
    HELM_REPO_URL  = 'https://azerez.github.io/devops0405-p3-Automation-CICD'
    REPO_SLUG      = 'azerez/devops0405-p3-Automation-CICD'
    GIT_NAME       = 'jenkins-ci'
    GIT_EMAIL      = 'ci@example.local'
    DOCKER_IMAGE   = 'erezazu/devops0405-docker-flask-app'
    K8S_NAMESPACE  = 'default'
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
      steps { powershell "helm lint ${env.HELM_DIR}" }
    }

    stage('Bump Chart Version (patch)') {
      when { changeset pattern: 'helm/**', comparator: 'ANT' }
      steps {
        script {
          // Chart.yaml
          def chartText = readFile("${env.HELM_DIR}/Chart.yaml")
          chartText = bumpChartYaml(chartText, env.GIT_SHA)     // @NonCPS
          writeFile file: "${env.HELM_DIR}/Chart.yaml", text: chartText

          // values.yaml (optional tag override)
          if (fileExists("${env.HELM_DIR}/values.yaml")) {
            def vals = readFile("${env.HELM_DIR}/values.yaml")
            vals = setTagInValues(vals, env.GIT_SHA)            // @NonCPS
            writeFile file: "${env.HELM_DIR}/values.yaml", text: vals
          }
          echo "Bumped chart; appVersion/tag -> ${env.GIT_SHA}"
        }
      }
    }

    stage('Package Chart') {
      when { changeset pattern: 'helm/**', comparator: 'ANT' }
      steps {
        powershell '''
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
            setlocal EnableDelayedExpansion
            for /f %%i in ('git rev-parse --abbrev-ref HEAD') do set CURR=%%i

            git config user.email "${GIT_EMAIL}"
            git config user.name  "${GIT_NAME}"

            git fetch origin gh-pages || echo no-remote
            if exist .git\\refs\\remotes\\origin\\gh-pages (
              git checkout -B gh-pages origin/gh-pages
              git reset --soft origin/gh-pages
            ) else (
              git checkout --orphan gh-pages
              git rm -rf .
            )

            mkdir ${PAGES_DIR} 2>nul
            type nul > ${PAGES_DIR}\\.nojekyll
            move /Y .release\\*.tgz ${PAGES_DIR}\\

            helm repo index ${PAGES_DIR} --url ${HELM_REPO_URL}

            git add ${PAGES_DIR}
            git commit -m "publish chart ${APP_NAME} ${GIT_SHA}" || echo nothing-to-commit
            git push https://%GHTOKEN%@github.com/${REPO_SLUG}.git gh-pages
            git checkout %CURR%
          """
        }
      }
    }

    stage('Build & Push Docker') {
      when {
        anyOf {
          changeset pattern: 'App/**', comparator: 'ANT'
          changeset pattern: 'app/**', comparator: 'ANT'
        }
      }
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKERHUB_USR', passwordVariable: 'DOCKERHUB_PSW')]) {
          powershell """
            \$ErrorActionPreference = 'Stop'
            docker login -u \$env:DOCKERHUB_USR -p \$env:DOCKERHUB_PSW
            docker build -t ${env.DOCKER_IMAGE}:${env.GIT_SHA} -t ${env.DOCKER_IMAGE}:latest App
            docker push ${env.DOCKER_IMAGE}:${env.GIT_SHA}
            docker push ${env.DOCKER_IMAGE}:latest
          """
        }
      }
    }

    stage('Deploy to minikube') {
      when {
        anyOf {
          changeset pattern: 'helm/**', comparator: 'ANT'
          changeset pattern: 'App/**', comparator: 'ANT'
          changeset pattern: 'app/**', comparator: 'ANT'
        }
      }
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG_FILE')]) {
          withEnv(["KUBECONFIG=${KUBECONFIG_FILE}"]) {
            powershell """
              helm upgrade --install ${env.APP_NAME} ${env.HELM_DIR} `
                --namespace ${env.K8S_NAMESPACE} --create-namespace `
                --set image.repository=${env.DOCKER_IMAGE} `
                --set image.tag=${env.GIT_SHA}
            """
          }
        }
      }
    }
  }
}

