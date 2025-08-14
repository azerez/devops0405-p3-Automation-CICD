pipeline {
  agent { label 'node01' } // עדכן לפי שם ה-agent שלך

  options {
    timestamps()
  }

  environment {
    IMAGE_REPO       = 'erezazu/devops0405-docker-flask-app'
    CHART_DIR        = 'helm/flaskapp'
    RELEASE          = 'flaskapp'
    MINIKUBE_PROFILE = 'minikube'
  }

  stages {

    stage('Checkout SCM') {
      steps { checkout scm }
    }

    stage('Init (capture SHA)') {
      steps {
        script {
          // Windows bat tends to echo path/prompt; take last line only
          def out  = bat(returnStdout: true, script: '@echo off\r\ngit rev-parse --short=7 HEAD').trim()
          def lines = out.readLines()
          env.GIT_SHA = lines ? lines[-1].trim() : out
          echo "GIT_SHA = ${env.GIT_SHA}"
        }
      }
    }

    stage('Detect Helm Changes') {
      steps {
        script {
          def out = bat(returnStdout: true, script: '@echo off\r\ngit diff --name-only HEAD~1..HEAD ^| findstr /R /C:".*" && ver >NUL').trim()
          def files = out.readLines().collect { it.replace('\\','/').trim() }
          def changed = files.any { it.startsWith("${env.CHART_DIR}/") }
          // fallback אם diff ריק (למשל ריצה ידנית)
          if (!changed) { changed = fileExists("${env.CHART_DIR}/values.yaml") }
          env.HELM_CHANGED = changed ? 'true' : 'false'
          echo "Changed files:\n${files.join('\n')}\n"
          echo "HELM_CHANGED = ${env.HELM_CHANGED}"
        }
      }
    }

    stage('Helm Lint') {
      when { expression { env.HELM_CHANGED == 'true' } }
      steps {
        dir("${env.CHART_DIR}") { bat 'helm lint .' }
      }
    }

    stage('Bump Chart Version (patch)') {
      when { expression { env.HELM_CHANGED == 'true' } }
      steps {
        script {
          def chartPath  = "${env.CHART_DIR}/Chart.yaml"
          def chart = readFile(file: chartPath, encoding: 'UTF-8')

          // --- מציאת גרסה בלי Regex Matcher (אין NotSerializable) ---
          def lines = chart.readLines()
          int vIdx = lines.findIndexOf { it.trim().toLowerCase().startsWith('version:') }
          if (vIdx < 0) { error "Cannot find 'version:' in ${chartPath}" }
          def versionStr = lines[vIdx].split(':', 2)[1].trim()
          def parts = versionStr.tokenize('.')
          if (parts.size() < 3) { error "version format not semver: ${versionStr}" }
          int patch = (parts[2] as int) + 1
          def newVersion = "${parts[0]}.${parts[1]}.${patch}"
          lines[vIdx] = "version: ${newVersion}"

          // appVersion
          int aIdx = lines.findIndexOf { it.trim().toLowerCase().startsWith('appversion:') }
          if (aIdx >= 0) {
            lines[aIdx] = "appVersion: \"${env.GIT_SHA}\""
          } else {
            lines << "appVersion: \"${env.GIT_SHA}\""
          }

          chart = lines.join(System.lineSeparator())
          writeFile file: chartPath, text: chart, encoding: 'UTF-8'

          echo "Chart updated: version -> ${newVersion}, appVersion -> ${env.GIT_SHA}"
        }
      }
    }

    stage('Package Chart') {
      when { expression { env.HELM_CHANGED == 'true' } }
      steps {
        bat '''
          if not exist ".release" mkdir ".release"
          helm package -d ".release" "%CHART_DIR%"
        '''
        archiveArtifacts artifacts: '.release/*.tgz', fingerprint: true
      }
    }

    stage('Publish to gh-pages') {
      when { expression { env.HELM_CHANGED == 'true' } }
      environment {
        GH_EMAIL = 'ci-bot@example.com'
        GH_NAME  = 'ci-bot'
        REPO_URL = 'https://github.com/azerez/devops0405-p3-Automation-CICD.git'
      }
      steps {
        withCredentials([string(credentialsId: 'gh_token', variable: 'GH_TOKEN')]) {
          bat '''
            @echo off
            setlocal enableextensions
            git config user.email "%GH_EMAIL%"
            git config user.name "%GH_NAME%"
            git config core.autocrlf false

            if not exist ".ghp" mkdir ".ghp"
            pushd .ghp

            if not exist ".git" (
              git init
              git remote add origin "%REPO_URL%"
            )
            git -c http.extraheader="AUTHORIZATION: bearer %GH_TOKEN%" fetch origin gh-pages || ver >NUL
            git checkout -B gh-pages || git checkout --orphan gh-pages

            if not exist "docs" mkdir "docs"
            popd

            rem Copy chart packages using xcopy to avoid FOR/backslash parsing issues
            xcopy /Y /I ".release\\*.tgz" ".ghp\\docs\\" >NUL

            pushd .ghp
            if exist docs\\index.yaml (
              helm repo index docs --merge docs\\index.yaml
            ) else (
              helm repo index docs
            )
            git add docs
            git commit -m "publish chart %GIT_SHA%" || ver >NUL
            git -c http.extraheader="AUTHORIZATION: bearer %GH_TOKEN%" push origin gh-pages
            popd
            endlocal
          '''
        }
      }
    }

    stage('Test (App quick checks)') {
      when { expression { env.HELM_CHANGED == 'true' } }
      steps { echo 'Quick checks passed (placeholder).' }
    }

    stage('Build & Push Docker') {
      when { expression { env.HELM_CHANGED == 'true' } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub', usernameVariable: 'DOCKERHUB_USER', passwordVariable: 'DOCKERHUB_PASS')]) {
          bat '''
            @echo off
            docker login -u %DOCKERHUB_USER% -p %DOCKERHUB_PASS%
            docker build -f App\\Dockerfile -t %IMAGE_REPO%:%GIT_SHA% App
            docker push %IMAGE_REPO%:%GIT_SHA%
          '''
        }
      }
    }

    stage('K8s Preflight') {
      when { expression { env.HELM_CHANGED == 'true' } }
      steps {
        script {
          def nodes = bat(returnStdout: true, script: '@echo off\r\nminikube -p %MINIKUBE_PROFILE% kubectl -- get nodes --no-headers').trim()
          def apiStatus = bat(returnStatus: true, script: '@echo off\r\nminikube -p %MINIKUBE_PROFILE% kubectl -- version --short')
          def ready = nodes.readLines().any { it.contains(' Ready ') }
          env.K8S_OK = (ready && apiStatus == 0) ? 'true' : 'false'
          echo "K8S_OK = ${env.K8S_OK}"
        }
      }
    }

    stage('Deploy to minikube') {
      when { expression { env.HELM_CHANGED == 'true' && env.K8S_OK == 'true' } }
      steps {
        bat '''
          @echo off
          echo ==== Helm upgrade ====
          helm upgrade --install %RELEASE% "%CHART_DIR%" ^
            --set image.repository=%IMAGE_REPO% ^
            --set image.tag=%GIT_SHA% ^
            --wait --timeout 180s

          echo ==== Get resources ====
          minikube -p %MINIKUBE_PROFILE% kubectl -- get deploy,svc,pods -o wide
        '''
      }
    }

    stage('Smoke Test') {
      when { expression { env.HELM_CHANGED == 'true' && env.K8S_OK == 'true' } }
      steps {
        bat '''
          @echo off
          echo ==== Rollout status ====
          minikube -p %MINIKUBE_PROFILE% kubectl -- rollout status deploy/%RELEASE% --timeout=120s

          echo ==== Get service URL ====
          for /f %%A in ('minikube -p %MINIKUBE_PROFILE% service %RELEASE% --url') do set SVC_URL=%%A
          echo URL=%SVC_URL%

          echo ==== Curl root ====
          curl -sS --max-time 10 "%SVC_URL%/" > curl_root.txt
          type curl_root.txt

          echo ==== Curl /healthz (optional) ====
          curl -sS --max-time 10 "%SVC_URL%/healthz" > curl_healthz.txt || ver >NUL
          type curl_healthz.txt || ver >NUL
        '''
      }
    }
  }

  post {
    always {
      echo "OK: HELM_CHANGED=${env.HELM_CHANGED}, SHA=${env.GIT_SHA}, K8S_OK=${env.K8S_OK}"
      cleanWs()
    }
  }
}
