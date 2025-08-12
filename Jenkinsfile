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
          // SHA נקי – בלי הדפסת ה-cmd prompt
          env.GIT_SHA = bat(returnStdout: true, script: '@echo off\r\ngit rev-parse --short HEAD').trim()
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
        // כל השינויים בקבצים – ב-PowerShell, עם SHA נקי שמחושב כאן
        powershell '''
$ErrorActionPreference = "Stop"
$chart = "helm/flaskapp/Chart.yaml"
$vals  = "helm/flaskapp/values.yaml"

# קח SHA נקי ישירות מ-git (לא מסתמך על משתני סביבה מהbat)
$sha = (git rev-parse --short HEAD).Trim()

# ----- Chart.yaml: bump patch + appVersion="SHA"
$txt = Get-Content -Raw -Encoding UTF8 $chart

# bump version X.Y.Z -> X.Y.(Z+1)
if ($txt -match '(?m)^version:\\s*(\\d+)\\.(\\d+)\\.(\\d+)') {
  $maj = [int]$Matches[1]; $min = [int]$Matches[2]; $pat = [int]$Matches[3] + 1
  $txt = [regex]::Replace($txt, '(?m)^(version:\\s*)(\\d+)\\.(\\d+)\\.(\\d+)', "`$1$maj.$min.$pat", 1)
} else {
  throw "version: X.Y.Z not found in Chart.yaml"
}

# appVersion -> "SHA" (אם אין – מוסיפים בסוף)
if ($txt -match '(?m)^appVersion:\\s*.*$') {
  $txt = [regex]::Replace($txt, '(?m)^appVersion:\\s*.*$', 'appVersion: "'+$sha+'"', 1)
} else {
  $txt = $txt.TrimEnd() + "`r`nappVersion: `"$sha`"`r`n"
}
Set-Content -Path $chart -Encoding UTF8 -Value $txt

# ----- values.yaml: image.repository + image.tag="SHA"
$v = Get-Content -Raw -Encoding UTF8 $vals

# ודא שיש image.repository נכון
if ($v -match '(?m)^\\s*repository:\\s*.*$') {
  $v = [regex]::Replace($v, '(?m)^(\\s*repository:\\s*).*$', '$1erezazu/devops0405-docker-flask-app', 1)
} else {
  # אם חסר, ננסה להוסיף בלוק image בסיסי
  if ($v -notmatch '(?m)^image:\\s*$') {
    $v = $v.TrimEnd() + "`r`nimage:`r`n  repository: erezazu/devops0405-docker-flask-app`r`n  tag: `"$sha`"`r`n  pullPolicy: IfNotPresent`r`n"
  }
}

# tag -> "SHA" (מחליף אם קיים, אחרת מוסיף)
if ($v -match '(?m)^\\s*tag:\\s*.*$') {
  $v = [regex]::Replace($v, '(?m)^(\\s*tag:\\s*).*$', '$1"'+$sha+'"' , 1)
} elseif ($v -match '(?m)^image:\\s*$') {
  $v = $v + "  tag: `"$sha`"`r`n"
}
Set-Content -Path $vals -Encoding UTF8 -Value $v

Write-Host "Bumped Chart.yaml and values.yaml to SHA $sha"
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

