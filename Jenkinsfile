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
          // current commit short SHA
          env.GIT_SHA = bat(returnStdout: true, script: 'git rev-parse --short HEAD').trim()

          def chartPath = "${HELM_DIR}/Chart.yaml"
          def valsPath  = "${HELM_DIR}/values.yaml"
          def chartText = readFile(chartPath)
          def lines     = chartText.readLines()

          // --- bump version: x.y.z -> x.y.(z+1) (no regex matcher kept) ---
          int verIdx = lines.findIndexOf { it.trim().startsWith('version:') }
          if (verIdx < 0) { error("version: not found in ${chartPath}") }
          def verStr = lines[verIdx].split(':', 2)[1].trim()   // after "version:"
          def parts  = verStr.tokenize('.')
          if (parts.size() < 3) { error("invalid SemVer in ${chartPath}: ${verStr}") }
          int major = parts[0] as int
          int minor = parts[1] as int
          int patch = (parts[2] as int) + 1
          def newVer = "${major}.${minor}.${patch}"
          lines[verIdx] = "version: ${newVer}"

          // --- set/append appVersion to current git sha ---
          int appIdx = lines.findIndexOf { it.trim().startsWith('appVersion:') }
          if (appIdx >= 0) { lines[appIdx] = "appVersion: ${env.GIT_SHA}" }
          else { lines += "appVersion: ${env.GIT_SHA}" }

          writeFile file: chartPath, text: lines.join("\n")

          // --- update image tag in values.yaml if 'tag:' line exists ---
          if (fileExists(valsPath)) {
            def vLines = readFile(valsPath).readLines()
            int tagIdx = vLines.findIndexOf { it.trim().startsWith('tag:') }
            if (tagIdx >= 0) {
              vLines[tagIdx] = '  tag: "' + env.GIT_SHA + '"'
              writeFile file: valsPath, text: vLines.join("\n")
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
[O            if (-not (git show-ref --verify --quiet refs/heads/gh-pages)) {
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

