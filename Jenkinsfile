/*
  Jenkinsfile — Windows agent (PowerShell). English-only comments.

  What this pipeline does:
  1) Checkout code
  2) Capture short git SHA
  3) Detect if any files changed under the Helm chart folder; set HELM_CHANGED=true/false
  4) If Helm changed: lint, bump Chart.yaml patch version, package chart, publish to gh-pages
  5) Build & push Docker image (tagged with SHA and latest)
  6) Deploy to minikube with Helm (image tag = SHA)
  7) Simple smoke test (rollout + HTTP /health)

  Notes:
  - We use triple-single-quoted strings in PowerShell steps to avoid Groovy $-interpolation issues.
  - We DO NOT use the env var name DOCKER_CONTEXT (Docker uses it). We use BUILD_CONTEXT_PATH instead.
*/

pipeline {
  agent any
  options { timestamps(); disableConcurrentBuilds() }

  environment {
    // App/chart basics
    APP_NAME           = 'flaskapp'
    CHART_DIR          = 'helm/flaskapp'   // path to your chart
    RELEASE_DIR        = '.release'        // where packaged .tgz files are placed

    // Docker image repo (adjust if needed)
    DOCKER_IMAGE       = 'erezazu/devops0405-docker-flask-app'

    // Kubernetes/Helm deploy target
    K8S_NAMESPACE      = 'default'

    // Helm repository branch (GitHub Pages)
    HELM_REPO_BRANCH   = 'gh-pages'

    // Git identity for CI commits
    GIT_EMAIL          = 'ci-bot@example.com'
    GIT_USER           = 'ci-bot'

    // Safe names for Docker build inputs (do not use DOCKER_CONTEXT)
    BUILD_DOCKERFILE   = 'Dockerfile'
    BUILD_CONTEXT_PATH = '.'
  }

  stages {

    stage('Checkout SCM') {
      steps {
        // Standard checkout (works in Multibranch as well)
        checkout scm
      }
    }

    stage('Init (capture SHA)') {
      steps {
        script {
          // Clean short SHA without prompt noise
          env.GIT_SHA = powershell(returnStdout: true, script: '''(git rev-parse --short HEAD).Trim()''').trim()
          echo "GIT_SHA=${env.GIT_SHA}"

          // Current branch (Multibranch provides BRANCH_NAME)
          env.CUR_BRANCH = env.BRANCH_NAME ?: 'main'
        }
      }
    }

    stage('Detect Changes') {
      steps {
        script {
          // Ensure we have remote branch data to diff against
          powershell '''git fetch origin $env:CUR_BRANCH'''

          // Compute diff range: merge-base with origin/<branch>; fallback to HEAD~1 if needed
          def base = powershell(returnStdout:true, script: '''
            $b = git merge-base HEAD origin/$env:CUR_BRANCH 2>$null
            if (-not $b) { $b = (git rev-parse HEAD~1) }
            $b.Trim()
          ''').trim()

          def head = powershell(returnStdout:true, script: '''(git rev-parse HEAD).Trim()''').trim()
          def diff = powershell(returnStdout:true, script: "git diff --name-only ${base} ${head}").trim()
          echo "Changed files:\n${diff}"

          // Mark HELM_CHANGED=true only if something inside CHART_DIR (or helm/) changed
          def changed = diff ? diff.readLines().any { it.startsWith("${env.CHART_DIR}/") || it.startsWith('helm/') } : false
          env.HELM_CHANGED = changed ? 'true' : 'false'
          echo "HELM_CHANGED=${env.HELM_CHANGED}"
        }
      }
    }

    stage('Helm Lint') {
      when { expression { fileExists("${env.CHART_DIR}/Chart.yaml") } }
      steps {
        // Lint the chart if it exists
        dir("${CHART_DIR}") {
          powershell '''helm lint .'''
        }
      }
    }

    stage('Bump Chart Version (patch)') {
      // Only bump when the chart changed (real-world behavior)
      when { expression { env.HELM_CHANGED == 'true' } }
      steps {
        dir("${CHART_DIR}") {
          // Increase patch version in Chart.yaml: x.y.z -> x.y.(z+1)
          powershell '''
            $p = Get-Content Chart.yaml -Raw
            if ($p -match "version:\\s*(\\d+)\\.(\\d+)\\.(\\d+)") {
              $maj=[int]$Matches[1]; $min=[int]$Matches[2]; $pat=([int]$Matches[3])+1
              $new = [regex]::Replace($p, "version:\\s*\\d+\\.\\d+\\.\\d+", ("version: {0}.{1}.{2}" -f $maj,$min,$pat), 1)
              Set-Content Chart.yaml $new -Encoding UTF8
              Write-Host "Bumped chart version to $maj.$min.$pat"
            } else { throw "Could not find version in Chart.yaml" }
          '''
          // Commit version change (skip CI to avoid loops)
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
        // Ensure output folder exists
        powershell "if (!(Test-Path '${RELEASE_DIR}')) { New-Item -ItemType Directory -Path '${RELEASE_DIR}' | Out-Null }"
        // Package the chart to .tgz in RELEASE_DIR
        dir("${CHART_DIR}") {
          powershell "helm package . -d ..\\..\\${RELEASE_DIR}"
        }
        // Archive artifacts for traceability
        archiveArtifacts artifacts: "${RELEASE_DIR}/*.tgz", fingerprint: true
      }
    }

    stage('Publish to gh-pages') {
      when { expression { env.HELM_CHANGED == 'true' } }
      steps {
        // Use a worktree to operate cleanly on gh-pages branch and update index.yaml
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

    stage('Locate Dockerfile') {
      steps {
        script {
          /*
            Auto-detect a Dockerfile if it is not at repo root.
            We output FILE=<fullpath> and CTX=<directory> and set
            BUILD_DOCKERFILE / BUILD_CONTEXT_PATH accordingly.
          */
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

          if (found) {
            def parts = found.readLines().collectEntries { ln ->
              def kv = ln.split('=',2); [(kv[0]): kv[1]]
            }
            env.BUILD_DOCKERFILE   = parts['FILE']
            env.BUILD_CONTEXT_PATH = parts['CTX']
          }
          echo "Docker build will use: -f ${env.BUILD_DOCKERFILE}  context=${env.BUILD_CONTEXT_PATH}"
        }
      }
    }

    stage('Build & Push Docker') {
      steps {
        /*
          Build with two tags: SHA and latest.
          IMPORTANT: We use BUILD_CONTEXT_PATH, not DOCKER_CONTEXT (to avoid Docker's own env var).
        */
        powershell """
          docker build -f "${env.BUILD_DOCKERFILE}" -t ${DOCKER_IMAGE}:${env.GIT_SHA} -t ${DOCKER_IMAGE}:latest "${env.BUILD_CONTEXT_PATH}"
          docker push ${DOCKER_IMAGE}:${env.GIT_SHA}
          docker push ${DOCKER_IMAGE}:latest
        """
      }
    }

    stage('Deploy to minikube') {
      steps {
        // Helm upgrade/install with the image tag set to the commit SHA
        powershell """
          helm upgrade --install ${APP_NAME} ${CHART_DIR} `
            --namespace ${K8S_NAMESPACE} --create-namespace `
            --set image.repository=${DOCKER_IMAGE} `
            --set image.tag=${env.GIT_SHA} `
            --set image.pullPolicy=IfNotPresent
        """
      }
    }

    stage('Smoke Test') {
      steps {
        // Wait for rollout and query the /health endpoint using NodePort
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
    success { echo "Build ${env.BUILD_NUMBER} OK. HELM_CHANGED=${env.HELM_CHANGED}, SHA=${env.GIT_SHA}" }
    always  { cleanWs() }
  }
}

