pipeline {
  agent any

  environment {
    APP_NAME      = 'flaskapp'
    HELM_DIR      = 'helm/flaskapp'
    PAGES_DIR     = 'docs'
    // Public Helm repo URL (GitHub Pages) — no trailing /docs
    HELM_REPO_URL = 'https://azerez.github.io/devops0405-p3-Automation-CICD'
    // GitHub owner/repo used for pushing to gh-pages
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
      // Run only if something under "helm/**" changed
      when { changeset pattern: 'helm/**', comparator: 'ANT' }
      steps {
        powershell 'helm lint $env:HELM_DIR'
      }
    }

    stage('Bump Chart Version (patch)') {
      when { changeset pattern: 'helm/**', comparator: 'ANT' }
      steps {
        script {
          // Short commit SHA for traceability
          env.GIT_SHA = bat(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
        }
        powershell '''
          $ErrorActionPreference = "Stop"
          $CHART = "$env:HELM_DIR/Chart.yaml"
          $VALS  = "$env:HELM_DIR/values.yaml"

          # Read and bump SemVer patch in Chart.yaml
          $content = Get-Content $CHART
          $m = Select-String -InputObject $content -Pattern '^\s*version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)\s*$'
          if (-not $m) { throw "version: not found in Chart.yaml" }
          $i = $m.LineNumber - 1
          $major = [int]$m.Matches[0].Groups[1].Value
          $minor = [int]$m.Matches[0].Groups[2].Value
          $patch = ([int]$m.Matches[0].Groups[3].Value) + 1
          $newVer = "$major.$minor.$patch"
          $content[$i] = "version: $newVer"

          # Set/append appVersion to current git sha
          $mApp = Select-String -InputObject $content -Pattern '^\s*appVersion:\s*'
          if ($mApp) {
            $content[$mApp.LineNumber[0]-1] = "appVersion: ${env:GIT_SHA}"
          } else {
            $content += "appVersion: ${env:GIT_SHA}"
          }
          Set-Content -NoNewline -Path $CHART -Value ($content -join "`n")

          # Update image tag in values.yaml if a 'tag:' key exists
          if (Test-Path $VALS) {
            $vals = Get-Content $VALS
            $mTag = Select-String -InputObject $vals -Pattern '^\s*tag:\s*'
            if ($mTag) {
              $vals[$mTag.LineNumber[0]-1] = "  tag: `"${env:GIT_SHA}`""
              Set-Content -NoNewline -Path $VALS -Value ($vals -join "`n")
            }
          }

          Write-Host "Bumped chart version to $newVer ; image tag -> ${env:GIT_SHA}"
        '''
      }
    }

    stage('Package Chart') {
      when { changeset pattern: 'helm/**', comparator: 'ANT' }
      steps {
        powershell '''
          $ErrorActionPreference = "Stop"
          if (Test-Path ".release") { Remove-Item -Recurse -Force ".release" }
          New-Item -ItemType Directory ".release" | Out-Null

          # Create the package directly into .release (no need to move afterward)
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

            # Move the chart package(s) into docs/
            Move-Item ".release\\*.tgz" "$env:PAGES_DIR\\" -Force

            # Rebuild index.yaml with the correct public URL
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

