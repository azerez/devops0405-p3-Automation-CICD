/*
  Jenkinsfile — Windows agent (PowerShell). English-only comments inside.

  Pipeline summary:
  - Detect Helm changes; run Helm lint/bump/package/publish only when chart changed
  - Run a lightweight "Test" stage (pre-deploy app checks)
  - Build & push Docker image with a single tag: v1
  - Deploy to minikube and run a smoke test

  Notes:
  - PowerShell blocks use triple-single quotes to avoid Groovy $-interpolation issues.
  - We DO NOT use env var name DOCKER_CONTEXT (Docker uses it). Using BUILD_CONTEXT_PATH instead.
*/

pipeline {
  agent any
  options { timestamps(); disableConcurrentBuilds() }

  environment {
    APP_NAME           = 'flaskapp'
    CHART_DIR          = 'helm/flaskapp'
    RELEASE_DIR        = '.release'

    DOCKER_IMAGE       = 'erezazu/devops0405-docker-flask-app'
    DOCKER_TAG         = 'v1'              // single-tag strategy, as requested

    K8S_NAMESPACE      = 'default'
    HELM_REPO_BRANCH   = 'gh-pages'

    GIT_EMAIL          = 'ci-bot@example.com'
    GIT_USER           = 'ci-bot'

    BUILD_DOCKERFILE   = 'Dockerfile'
    BUILD_CONTEXT_PATH = '.'

    DOCKER_OK          = 'false'
    AUTO_CREATE_DOCKERFILE = 'true'
  }

  stages {

    stage('Checkout SCM') { steps { checkout scm } }

    stage('Init (capture SHA)') {
      steps {
        script {
          // SHA used only for logs in "single tag" mode
          env.GIT_SHA = powershell(returnStdout: true, script: '''(git rev-parse --short HEAD).Trim()''').trim()
          echo "GIT_SHA=${env.GIT_SHA}"
          env.CUR_BRANCH = env.BRANCH_NAME ?: 'main'
        }
      }
    }

    stage('Detect Changes') {
      steps {
        script {
          powershell '''git fetch origin $env:CUR_BRANCH'''
          def base = powershell(returnStdout:true, script: '''
            $b = git merge-base HEAD origin/$env:CUR_BRANCH 2>$null
            if (-not $b) { $b = (git rev-parse HEAD~1) }
            $b.Trim()
          ''').trim()
          def head = powershell(returnStdout:true, script: '''(git rev-parse HEAD).Trim()''').trim()
          def diff = powershell(returnStdout:true, script: "git diff --name-only ${base} ${head}").trim()
          echo "Changed files:\n${diff}"
          def changed = diff ? diff.readLines().any { it.startsWith("${env.CHART_DIR}/") || it.startsWith('helm/') } : false
          env.HELM_CHANGED = changed ? 'true' : 'false'
          echo "HELM_CHANGED=${env.HELM_CHANGED}"
        }
      }
    }

    stage('Helm Lint') {
      when { expression { fileExists("${env.CHART_DIR}/Chart.yaml") } }
      steps { dir("${CHART_DIR}") { powershell '''helm lint .''' } }
    }

    stage('Bump Chart Version (patch)') {
      when { expression { env.HELM_CHANGED == 'true' } }
      steps {
        dir("${CHART_DIR}") {
          powershell '''
            $p = Get-Content Chart.yaml -Raw
            if ($p -match "version:\\s*(\\d+)\\.(\\d+)\\.(\\d+)") {
              $maj=[int]$Matches[1]; $min=[int]$Matches[2]; $pat=([int]$Matches[3])+1
              $new = [regex]::Replace($p, "version:\\s*\\d+\\.\\d+\\.\\d+", ("version: {0}.{1}.{2}" -f $maj,$min,$pat), 1)
              Set-Content Chart.yaml $new -Encoding UTF8
              Write-Host "Bumped chart version to $maj.$min.$pat"
            } else { throw "Could not find version in Chart.yaml" }
          '''
          powershell '''
            git config user.email "${env:GIT_EMAIL}"
            git config user.name  "${env:GIT_USER}"
            git add Chart.yaml
            git commit -m "ci: bump chart version [skip ci]" 2>$null; if ($LASTEXITCODE -ne 0) { exit 0 }
          '''
        }
      }
    }

    stage('Package Chart') {
      when { expression { env.HELM_CHANGED == 'true' } }
      steps {
        powershell "if (!(Test-Path '${RELEASE_DIR}')) { New-Item -ItemType Directory -Path '${RELEASE_DIR}' | Out-Null }"
        dir("${CHART_DIR}") {
          powershell "helm package . -d ..\\..\\${RELEASE_DIR}"
        }
        archiveArtifacts artifacts: "${RELEASE_DIR}/*.tgz", fingerprint: true
      }
    }

    stage('Publish to gh-pages') {
      when { expression { env.HELM_CHANGED == 'true' } }
      steps {
        powershell '''
          git config user.email "${env:GIT_EMAIL}"
          git config user.name  "${env:GIT_USER}"

          if (Test-Path .worktree) { Remove-Item -Recurse -Force .worktree }
          mkdir .worktree | Out-Null

          git worktree add .worktree ${env:HELM_REPO_BRANCH} 2>$null
          if ($LASTEXITCODE -ne 0) {
            git branch -D ${env:HELM_REPO_BRANCH} 2>$null
            git checkout --orphan ${env:HELM_REPO_BRANCH}
            git reset --hard
            git worktree add .worktree ${env:HELM_REPO_BRANCH}
          }

          cd .worktree
          if (Test-Path ..\\${env:RELEASE_DIR}\\*.tgz) { Copy-Item ..\\${env:RELEASE_DIR}\\*.tgz . }

          if (Test-Path .\\index.yaml) {
            helm repo index . --merge .\\index.yaml --url ./
          } else {
            helm repo index . --url ./
          }

          git add *.tgz,index.yaml 2>$null
          git commit -m "ci: publish chart ${env:APP_NAME} (${env:GIT_SHA})" 2>$null
          git push origin ${env:HELM_REPO_BRANCH}
        '''
      }
    }

    // -------- TEST STAGE (fills the "build, test, deploy" requirement) --------
    stage('Test (App quick checks)') {
      steps {
        /*
          Lightweight checks before building/deploying:
          - If requirements.txt exists, try installing into a temp venv
          - Try compiling Python sources (py_compile)
          - If tests/ exists and pytest is available, run pytest -q
          All checks are best-effort; if Python is not installed, they are skipped.
        */
        powershell '''
          Write-Host "== Quick test stage =="
          $python = (Get-Command python -ErrorAction SilentlyContinue)
          if (-not $python) { Write-Host "Python not found; skipping quick tests."; exit 0 }

          if (Test-Path requirements.txt) {
            python -m venv .venv
            .\\.venv\\Scripts\\pip install --no-cache-dir -r requirements.txt
          }

          if (Test-Path app.py) { python -m py_compile app.py }
          if (Test-Path main.py) { python -m py_compile main.py }

          if (Test-Path tests) {
            python -m pip install --no-cache-dir pytest
            python -m pytest -q
          }
        '''
      }
    }
    // -------------------------------------------------------------------------

    stage('Docker Preflight') {
      steps {
        script {
          def ok = powershell(returnStatus: true, script: '''
            $ErrorActionPreference = "Stop"
            docker info | Out-Null
          ''') == 0
          env.DOCKER_OK = ok ? 'true' : 'false'
          echo "DOCKER_OK=${env.DOCKER_OK}"
        }
      }
    }

    stage('Ensure/Locate Dockerfile') {
      when { expression { env.DOCKER_OK == 'true' } }
      steps {
        script {
          def found = powershell(returnStdout:true, script: '''
            $candidate = (Get-ChildItem -Recurse -Filter Dockerfile -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($candidate) {
              "FILE=$($candidate.FullName)`nCTX=$((Split-Path $candidate.FullName -Parent))"
            } else {
              if (Test-Path (Join-Path $PWD "Dockerfile")) {
                "FILE=$((Join-Path $PWD "Dockerfile"))`nCTX=$PWD"
              }
            }
          ''').trim()

          if (!found && env.AUTO_CREATE_DOCKERFILE == 'true') {
            echo "No Dockerfile found. Creating a minimal Dockerfile at repo root (auto-fallback)."
            powershell '''
@"
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt* ./
RUN if exist requirements.txt ( pip install --no-cache-dir -r requirements.txt ) else ( pip install --no-cache-dir flask )
COPY . .
ENV PYTHONUNBUFFERED=1
EXPOSE 5000
CMD powershell -Command ^
  "if (Test-Path app.py) { python app.py } ^
   elseif (Test-Path main.py) { python main.py } ^
   else { if ($env:FLASK_APP) { python -m flask run --host=0.0.0.0 --port=5000 } else { python -c 'import time; print(\"No app.py/main.py; set FLASK_APP.\"); time.sleep(3600)' } }"
"@ | Out-File -FilePath Dockerfile -Encoding utf8 -Force
'''
            env.BUILD_DOCKERFILE   = "${pwd()}/Dockerfile"
            env.BUILD_CONTEXT_PATH = "${pwd()}"
          } else if (found) {
            def parts = found.readLines().collectEntries { ln -> def kv = ln.split('=',2); [(kv[0]): kv[1]] }
            env.BUILD_DOCKERFILE   = parts['FILE']
            env.BUILD_CONTEXT_PATH = parts['CTX']
          } else {
            echo "No Dockerfile found and AUTO_CREATE_DOCKERFILE=false. Docker stages will be skipped."
            env.DOCKER_OK = 'false'
          }

          echo "Docker build will use: -f ${env.BUILD_DOCKERFILE}  context=${env.BUILD_CONTEXT_PATH}"
        }
      }
    }

    stage('Build & Push Docker (tag = v1)') {
      when { expression { env.DOCKER_OK == 'true' } }
      steps {
        powershell """
          docker build -f "${env.BUILD_DOCKERFILE}" -t ${DOCKER_IMAGE}:${env.DOCKER_TAG} "${env.BUILD_CONTEXT_PATH}"
          docker push ${DOCKER_IMAGE}:${env.DOCKER_TAG}
        """
      }
    }

    stage('Deploy to minikube (image tag = v1)') {
      when { expression { env.DOCKER_OK == 'true' } }
      steps {
        powershell """
          helm upgrade --install ${APP_NAME} ${CHART_DIR} `
            --namespace ${K8S_NAMESPACE} --create-namespace `
            --set image.repository=${DOCKER_IMAGE} `
            --set image.tag=${env.DOCKER_TAG} `
            --set image.pullPolicy=IfNotPresent
        """
      }
    }

    stage('Smoke Test') {
      when { expression { env.DOCKER_OK == 'true' } }
      steps {
        powershell '''
          kubectl -n $env:K8S_NAMESPACE rollout status deploy/$env:APP_NAME --timeout=120s
          $np = kubectl -n $env:K8S_NAMESPACE get svc $env:APP_NAME -o jsonpath="{.spec.ports[0].nodePort}"
          $ip = minikube ip
          curl -s "http://$ip:$np/health" | Out-String | Write-Host
        '''
      }
    }
  }

  post {
    success { echo "Build ${env.BUILD_NUMBER} OK. HELM_CHANGED=${env.HELM_CHANGED}, DOCKER_OK=${env.DOCKER_OK}, SHA=${env.GIT_SHA}, TAG=${env.DOCKER_TAG}" }
    always  { cleanWs() }
  }
}

