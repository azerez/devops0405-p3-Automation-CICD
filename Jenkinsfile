pipeline {
  agent any
  options { timestamps() }

  environment {
    APP_NAME      = 'flaskapp'
    CHART_DIR     = 'helm/flaskapp'
    RELEASE_DIR   = '.release'
    DOCKER_IMAGE  = 'erezazu/devops0405-docker-flask-app'
    K8S_NAMESPACE = 'default'
  }

  stages {

    stage('Checkout SCM') {
      steps { checkout scm }
    }

    stage('Init (capture SHA)') {
      steps {
        script {
          env.GIT_SHA = bat(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
          echo "GIT_SHA = ${env.GIT_SHA}"
        }
      }
    }

    stage('Helm Lint') {
      steps {
        dir("${CHART_DIR}") {
          bat 'helm lint .'
        }
      }
    }

    stage('Bump Chart Version (patch)') {
      steps {
        // עושים את כל העדכונים בקבצי ה-YAML דרך PowerShell כדי להימנע מ־Sandbox/Regex ב-Groovy
        powershell '''
$ErrorActionPreference = "Stop"
$chart = "helm/flaskapp/Chart.yaml"
$vals  = "helm/flaskapp/values.yaml"

# ---- Bump version X.Y.Z -> X.Y.(Z+1)
$txt = Get-Content -Raw $chart
if ($txt -match '(?m)^version:\\s*(\\d+)\\.(\\d+)\\.(\\d+)') {
  $major = [int]$Matches[1]; $minor = [int]$Matches[2]; $patch = [int]$Matches[3] + 1
  $txt = [regex]::Replace($txt, '(?m)^(version:\\s*)(\\d+)\\.(\\d+)\\.(\\d+)', "`$1$major.$minor.$patch", 1)
} else {
  throw "version: X.Y.Z not found in Chart.yaml"
}

# ---- appVersion -> GIT_SHA
if ($txt -match '(?m)^appVersion:\\s*.*$') {
  $txt = [regex]::Replace($txt, '(?m)^appVersion:\\s*.*$', "appVersion: `"$env:GIT_SHA`"")
} else {
  $txt = $txt.TrimEnd() + "`r`nappVersion: `"$env:GIT_SHA`"`r`n"
}
Set-Content -NoNewline -Path $chart -Value $txt

# ---- values.yaml: image.repository + image.tag
$v = Get-Content -Raw $vals
$v = [regex]::Replace($v, '(?m)^(\\s*repository:\\s*).*$', "`$1erezazu/devops0405-docker-flask-app")
$v = [regex]::Replace($v, '(?m)^(\\s*tag:\\s*).*$', "`$1`"$env:GIT_SHA`"")
Set-Content -NoNewline -Path $vals -Value $v

Write-Host "Bumped Chart.yaml and values.yaml to SHA $env:GIT_SHA"
'''
      }
    }

    stage('Package Chart') {
      steps {
        bat 'if not exist ".release" mkdir .release'
        bat "helm package -d \"${RELEASE_DIR}\" \"${CHART_DIR}\""
      }
    }

    stage('Publish to gh-pages') {
      when { branch 'main' }
      steps {
        withCredentials([string(credentialsId: 'GH_TOKEN', variable: 'GH_TOKEN')]) {
          // שומרים את ה-tgz זמנית לפני git stash/checkout כדי שלא ייעלם
          bat '''
if not exist _chart_out mkdir _chart_out
copy /Y .release\\*.tgz _chart_out\\ >NUL 2>&1

git config --global user.name "jenkins-ci"
git config --global user.email "jenkins@example.com"
git config --global credential.helper ""

git fetch origin gh-pages 1>NUL 2>NUL || ver >NUL
git add -A
git stash --include-untracked 1>NUL 2>NUL
git checkout -B gh-pages

if not exist docs mkdir docs
move /Y _chart_out\\*.tgz docs\\ >NUL 2>&1
rmdir /S /Q _chart_out 2>NUL

if exist docs\\index.yaml (
  helm repo index docs --merge docs\\index.yaml
) else (
  helm repo index docs
)

type NUL > docs\\.nojekyll

set REMOTE=https://x-access-token:%GH_TOKEN%@github.com/azerez/devops0405-p3-Automation-CICD.git
git add docs
git commit -m "publish chart %GIT_SHA%" || ver >NUL
git push %REMOTE% HEAD:gh-pages --force
'''
        }
      }
    }

    stage('Build & Push Docker') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds',
                                          usernameVariable: 'DOCKERHUB_USER',
                                          passwordVariable: 'DOCKERHUB_PASS')]) {
          bat """
docker login -u %DOCKERHUB_USER% -p %DOCKERHUB_PASS%
docker build -t ${DOCKER_IMAGE}:${env.GIT_SHA} .
docker push ${DOCKER_IMAGE}:${env.GIT_SHA}
"""
        }
      }
    }

    stage('Deploy to minikube') {
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
          bat """
helm upgrade --install ${APP_NAME} ${CHART_DIR} ^
  --namespace ${K8S_NAMESPACE} ^
  --set image.repository=${DOCKER_IMAGE} ^
  --set image.tag=${env.GIT_SHA} ^
  --set image.pullPolicy=IfNotPresent
"""
        }
      }
    }
  }

  post {
    always { cleanWs() }
  }
}

