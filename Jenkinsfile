pipeline {
  agent any
  options { timestamps(); disableConcurrentBuilds() }

  environment {
    APP_NAME         = 'flaskapp'
    CHART_DIR        = 'helm/flaskapp'
    RELEASE_DIR      = '.release'
    DOCKER_IMAGE     = 'erezazu/devops0405-docker-flask-app'
    K8S_NAMESPACE    = 'default'
    HELM_REPO_BRANCH = 'gh-pages'
    GIT_EMAIL        = 'ci-bot@example.com'
    GIT_USER         = 'ci-bot'
  }

  stages {
    stage('Checkout SCM') { steps { checkout scm } }

    stage('Init (capture SHA)') {
      steps {
        script {
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

          def changed = diff.readLines().any { it.startsWith("${env.CHART_DIR}/") || it.startsWith('helm/') }
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
          if (Test-Path .\\index.yaml) { helm repo index . --merge .\\index.yaml --url ./ } else { helm repo index . --url ./ }

          git add *.tgz,index.yaml 2>$null
          git commit -m "ci: publish chart ${env:APP_NAME} (${env:GIT_SHA})" 2>$null
          git push origin ${env:HELM_REPO_BRANCH}
        '''
      }
    }

    stage('Build & Push Docker') {
      steps {
        powershell """
          docker build -t ${DOCKER_IMAGE}:${env.GIT_SHA} -t ${DOCKER_IMAGE}:latest .
          docker push ${DOCKER_IMAGE}:${env.GIT_SHA}
          docker push ${DOCKER_IMAGE}:latest
        """
      }
    }

    stage('Deploy to minikube') {
      steps {
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

