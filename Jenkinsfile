pipeline {
  agent any

  environment {
    APP_NAME      = 'flaskapp'
    HELM_DIR      = 'helm/flaskapp'
    PAGES_DIR     = 'docs'
    HELM_REPO_URL = 'https://azerez.github.io/devops0405-p3-Automation-CICD'
    REPO_SLUG     = 'azerez/devops0405-p3-Automation-CICD'   // owner/repo
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
          // short SHA via PowerShell (last line only)
          def out = powershell(returnStdout: true, script: '(git rev-parse --short HEAD) | Select-Object -Last 1')
          env.GIT_SHA = out.trim()

          def chartPath = "${HELM_DIR}/Chart.yaml"
          def valsPath  = "${HELM_DIR}/values.yaml"
          def lines     = readFile(chartPath).readLines()

          // bump x.y.z -> x.y.(z+1)
          int verIdx = lines.findIndexOf { it.trim().startsWith('version:') }
          if (verIdx < 0) { error("version: not found in ${chartPath}") }
          def verStr = lines[verIdx].split(':', 2)[1].trim()
          def parts  = verStr.tokenize('.')
          int major = parts[0] as int
          int minor = parts[1] as int
          int patch = (parts[2] as int) + 1
          def newVer = "${major}.${minor}.${patch}"
          lines[verIdx] = "version: ${newVer}"

          // appVersion -> current SHA
          int appIdx = lines.findIndexOf { it.trim().startsWith('appVersion:') }
          if (appIdx >= 0) lines[appIdx] = "appVersion: ${env.GIT_SHA}"
          else lines += "appVersion: ${env.GIT_SHA}"

          writeFile file: chartPath, text: lines.join("\n")

          // update image tag in values.yaml if present
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
          bat """
          @echo off
          setlocal enabledelayedexpansion

          for /f "delims=" %%i in ('git rev-parse --abbrev-ref HEAD') do set CURR=%%i

          git config user.email "%GIT_EMAIL%"
          git config user.name  "%GIT_NAME%"

          rem fetch remote gh-pages info
          git fetch origin gh-pages 2>nul

          rem Base local gh-pages on origin/gh-pages if exists; else create orphan
          git rev-parse --verify origin/gh-pages >nul 2>&1
          if errorlevel 1 (
            echo No remote gh-pages found -> creating orphan
            git checkout --orphan gh-pages
            git rm -rf . 2>nul
          ) else (
            echo Using remote origin/gh-pages as base
            git checkout -B gh-pages origin/gh-pages
          )

          if not exist "%PAGES_DIR%" mkdir "%PAGES_DIR%"
          if not exist "%PAGES_DIR%\\.nojekyll" type nul > "%PAGES_DIR%\\.nojekyll"

          move /y ".release\\*.tgz" "%PAGES_DIR%\\"

          helm repo index "%PAGES_DIR%" --url %HELM_REPO_URL%

          git add "%PAGES_DIR%"
          git commit -m "publish chart %APP_NAME% %GIT_SHA%" || echo Nothing to commit

          git push https://%GHTOKEN%@github.com/%REPO_SLUG%.git gh-pages
          if errorlevel 1 (
            echo Push failed. Aborting.
            exit /b 1
          )

          git checkout "!CURR!"
          endlocal
          """
        }
      }
    }
  }
}

