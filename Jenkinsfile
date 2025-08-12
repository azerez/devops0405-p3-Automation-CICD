pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    skipDefaultCheckout(false)
  }

  environment {
    APP_NAME         = 'flaskapp'
    CHART_DIR        = 'helm/flaskapp'            // נתיב הצ'ארט
    RELEASE_DIR      = '.release'                 // פלט החבילות
    DOCKER_IMAGE     = 'erezazu/devops0405-docker-flask-app'
    DOCKER_TAG       = "${env.BUILD_NUMBER}"
    K8S_NAMESPACE    = 'default'
    HELM_REPO_BRANCH = 'gh-pages'                 // רפו ה-Helm (GitHub Pages)
    GIT_EMAIL        = 'ci-bot@example.com'
    GIT_USER         = 'ci-bot'
  }

  stages {

    stage('Checkout SCM') {
      steps {
        checkout scm
      }
    }

    stage('Init (capture SHA)') {
      steps {
        script {
          def out = bat(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
          env.GIT_SHA = out
          echo "GIT_SHA=${env.GIT_SHA}"
        }
      }
    }

    stage('Detect Changes') {
      steps {
        script {
          // מזהה קבצים שהשתנו בקומיט האחרון / לעומת ה-merge-base
          // יעיל במולטי-בראנץ' ו-PRs
          def range = bat(script: 'git merge-base HEAD origin/${BRANCH_NAME} > base.txt & git rev-parse HEAD > head.txt', returnStdout: true)
          def base = readFile('base.txt').trim()
          def head = readFile('head.txt').trim()
          def diff = bat(script: "git diff --name-only ${base} ${head}", returnStdout: true).trim()

          echo "Changed files:\n${diff}"

          // האם יש שינוי בתוך תיקיית ה-Helm?
          env.HELM_CHANGED = (diff.readLines().any { it.startsWith("${CHART_DIR}/") || it.startsWith('helm/') }) ? 'true' : 'false'
          echo "HELM_CHANGED=${env.HELM_CHANGED}"
        }
      }
    }

    stage('Helm Lint') {
      when { expression { fileExists("${env.CHART_DIR}/Chart.yaml") } }
      steps {
        dir("${CHART_DIR}") {
          bat 'helm lint .'
        }
      }
    }

    stage('Bump Chart Version (patch)') {
      when { expression { env.HELM_CHANGED == 'true' } }
      steps {
        dir("${CHART_DIR}") {
          // PowerShell: מעלה את ה-patch ב-Chart.yaml
          bat '''
powershell -NoProfile -Command ^
  $p=Get-Content Chart.yaml -Raw; ^
  if($p -match "version:\\s*(\\d+)\\.(\\d+)\\.(\\d+)"){ ^
    $maj=[int]$Matches[1]; $min=[int]$Matches[2]; $pat=[int]$Matches[3]+1; ^
    $new=$p -replace "version:\\s*\\d+\\.\\d+\\.\\d+","version: $maj.$min.$pat"; ^
    Set-Content -Path Chart.yaml -Value $new -Encoding UTF8; ^
    Write-Host ("Bumped chart version to {0}.{1}.{2}" -f $maj,$min,$pat) ^
  } else { ^
    Write-Error "Could not find version in Chart.yaml" ^
  }
'''
          // מוסיף קומיט קטן לגרסה
          bat '''
git config user.email "${GIT_EMAIL}"
git config user.name  "${GIT_USER}"
git add Chart.yaml
git commit -m "ci: bump chart version [skip ci]" || echo "No version change to commit"
'''
        }
      }
    }

    stage('Package Chart') {
      when { expression { env.HELM_CHANGED == 'true' } }
      steps {
        bat "if not exist ${RELEASE_DIR} mkdir ${RELEASE_DIR}"
        dir("${CHART_DIR}") {
          bat "helm package . -d ../..\\${RELEASE_DIR}"
        }
        archiveArtifacts artifacts: "${RELEASE_DIR}/*.tgz", fingerprint: true
      }
    }

    stage('Publish to gh-pages') {
      when { expression { env.HELM_CHANGED == 'true' } }
      steps {
        script {
          bat '''
git config user.email "${GIT_EMAIL}"
git config user.name  "${GIT_USER}"

REM מכין worktree ל-gh-pages
if exist .worktree rd /s /q .worktree
mkdir .worktree
git worktree add .worktree ${HELM_REPO_BRANCH} || (git branch -D ${HELM_REPO_BRANCH} & git checkout --orphan ${HELM_REPO_BRANCH} & git reset --hard & git worktree add .worktree ${HELM_REPO_BRANCH})

cd .worktree

REM מעדכן index.yaml (merge כדי לשמר היסטוריה)
helm repo index ..\\${RELEASE_DIR} --merge index.yaml --url ./

copy ..\\${RELEASE_DIR}\\*.tgz .\\

git add *.tgz index.yaml
git commit -m "ci: publish chart ${APP_NAME} (${GIT_SHA})" || echo "Nothing to commit"
git push origin ${HELM_REPO_BRANCH}
'''
        }
      }
    }

    stage('Build & Push Docker') {
      steps {
        bat """
docker build -t ${DOCKER_IMAGE}:${GIT_SHA} -t ${DOCKER_IMAGE}:latest .
docker push ${DOCKER_IMAGE}:${GIT_SHA}
docker push ${DOCKER_IMAGE}:latest
"""
      }
    }

    stage('Deploy to minikube') {
      steps {
        // משתמשים ב-helm release עם תדמית מה-SHA
        bat """
helm upgrade --install ${APP_NAME} ${CHART_DIR} ^
  --namespace ${K8S_NAMESPACE} --create-namespace ^
  --set image.repository=${DOCKER_IMAGE} ^
  --set image.tag=${GIT_SHA} ^
  --set image.pullPolicy=IfNotPresent
"""
      }
    }

    stage('Smoke Test') {
      steps {
        // דוגמה פשוטה: המתנה ל-rollout ואז curl לשירות
        bat """
kubectl -n ${K8S_NAMESPACE} rollout status deploy/${APP_NAME} --timeout=120s
for /f "tokens=*" %%i in ('kubectl -n ${K8S_NAMESPACE} get svc ${APP_NAME} -o jsonpath="{.spec.ports[0].nodePort}"') do set NODEPORT=%%i
for /f "tokens=*" %%i in ('minikube ip') do set MIP=%%i
curl -s http://%MIP%:%NODEPORT%/health || exit /b 1
"""
      }
    }
  }

  post {
    success {
      echo "✅ Build ${env.BUILD_NUMBER} completed. Chart publish? ${env.HELM_CHANGED}"
    }
    always {
      cleanWs()
    }
  }
}

