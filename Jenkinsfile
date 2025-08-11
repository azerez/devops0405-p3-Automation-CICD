pipeline {
  agent any

  environment {
    APP_NAME      = 'flaskapp'
    HELM_DIR      = 'helm/flaskapp'
    PAGES_DIR     = 'docs'
    HELM_REPO_URL = 'https://azerez.github.io/devops0405-p3-Automation-CICD'
    REPO_SLUG     = 'azerez/devops0405-p3-Automation-CICD'
    GIT_NAME      = 'jenkins-ci'
    GIT_EMAIL     = 'ci@example.local'
  }

  options { timestamps() }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Helm Lint') {
      when { changeset pattern: 'helm/**', comparator: 'ANT' }
      steps { powershell 'helm lint $env:HELM_DIR' }
    }

    stage('Bump Chart Version (patch)') {
      when { changeset pattern: 'helm/**', comparator: 'ANT' }
      steps {
        script {
          // Short commit SHA for traceability
          env.GIT_SHA = bat(returnStdout: true, script: 'git rev-parse --short HEAD').trim()

          def chartPath = "${HELM_DIR}/Chart.yaml"
          def valsPath  = "${HELM_DIR}/values.yaml"
          def chart     = readFile(chartPath)

          // bump version: x.y.z -> x.y.(z+1)
          def m = (chart =~ /(?m)^\s*version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)/)
          if (!m.find()) { error("version: not found in ${chartPath}") }
          int major = m.group(1) as int
          int minor = m.group(2) as int
          int patch = (m.group(3) as int) + 1
          def newVer = "${major}.${minor}.${patch}"
          chart = chart.replaceFirst(/(?m)^\s*version:\s*[0-9]+\.[0-9]+\.[0-9]+/, "version: ${newVer}")

          // set/append appVersion to current git sha
          if ((chart =~ /(?m)^\s*appVersion:/).find()) {
            chart = chart.replaceFirst(/(?m)^\s*appVersion:\s*.*/, "appVersion: ${env.GIT_SHA}")
          } else {
            chart = chart + "\nappVersion: ${env.GIT_SHA}\n"
          }
          writeFile(file: chartPath, text: chart)

          // update image tag in values.yaml if 'tag:' exists
          if (fileExists(valsPath)) {
            def vals = readFile(valsPath)
            if ((vals =~ /(?m)^\s*tag:\s*/).find()) {
              vals = vals.replaceFirst(/(?m)^\s*tag:\s*.*/, "  tag: \"${env.GIT_SHA}\"")
              writeFile(file: valsPath, text: vals)
            }
          }

          echo "Bumped chart version to ${newVer}; image tag -> ${env.GIT_SHA}"
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
          # Create the package directly into .release (no move needed)
          helm package $env:HELM_DIR --destination .release
        '''
      }
    }

    stage('Publish to gh-pages') {
      when { changeset pattern: 'helm/**', comparator: 'ANT' }
      steps {
        withCredentials([string(credentialsId: 'github-token', variable: 'GHTOKEN')]) {
          powershell '''
            $ErrorActionPreference = "Stop"
            $CURR = (git rev-parse --abbrev-ref HEAD).Trim()

            git config user.email "$env:GIT_EMAIL"
            git config user.name  "$env:GIT_NAME"

            git fetch origin gh-pages 2>$null
            if (-not (git show-ref --verify --quiet refs/heads/gh-pages)) {
              git checkout --orphan gh-pages
              git rm -rf . 2>$null
            } else {
              git checkout gh-pages
            }

            New-Item -ItemType Directory "$env:PAGES_DIR" -Force | Out-Null
            New-Item -ItemType File "$env:PAGES_DIR/.nojekyll" -Force | Out-Null
            Move-Item ".release\\*.tgz" "$env:PAGES_DIR\\" -Force

            helm repo index "$env:PAGES_DIR" --url $env:HELM_REPO_URL

            git add $env:PAGES_DIR
            git commit -m "publish chart $env:APP_NAME $env:GIT_SHA" 2>$null; if ($LASTEXITCODE -ne 0) { Write-Host "Nothing to commit"; }

            git push "https://$env:GHTOKEN@github.com/$env:REPO_SLUG.git" gh-pages

            git checkout $CURR
          '''
        }
      }
    }
  }
}

