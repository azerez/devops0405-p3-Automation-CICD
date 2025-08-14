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
          def sha = bat(returnStdout: true, script: 'git rev-parse --short=7 HEAD').trim()
          env.GIT_SHA = sha
          echo "GIT_SHA = ${env.GIT_SHA}"
        }
      }
    }

    stage('Detect Helm Changes') {
      steps {
        script {
          def diff = bat(returnStdout: true, script: 'git diff --name-only HEAD~1..HEAD || ver >NUL').trim()
          def changed = diff.readLines().any { it.replace('\\','/').startsWith("${env.CHART_DIR}/") }
          if (!changed) { changed = fileExists("${env.CHART_DIR}/values.yaml") }
          env.HELM_CHANGED = changed ? 'true' : 'false'
          echo "Changed files:\n${diff}\n"
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
          def valuesPath = "${env.CHART_DIR}/values.yaml"
          def chart = readFile(file: chartPath, encoding: 'UTF-8')

          def m = (chart =~ /(?m)^version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)/)
          if (!m.find()) { error "Cannot find 'version:' in ${chartPath}" }
          def major = m.group(1) as int
          def minor = m.group(2) as int
          def patch = (m.group(3) as int) + 1
          def newVersion = "${major}.${minor}.${patch}"

          chart = chart.replaceFirst(/(?m)^version:\s*[0-9]+\.[0-9]+\.[0-9]+/, "version: ${newVersion}")
          if (chart =~ /(?m)^appVersion:/) {
            chart = chart.replaceFirst(/(?m)^appVersion:\s*.*/, "appVersion: \"${env.GIT_SHA}\"")
          } else {
            chart += "\nappVersion: \"${env.GIT_SHA}\"\n"
          }
          writeFile file: chartPath, text: chart, encoding: 'UTF-8'

          if (fileExists(valuesPath)) {
            def vals = readFile(file: valuesPath, encoding: 'UTF-8')
            // עדכון tag
            if (vals =~ /(?m)^\s*tag:\s*.+/) {
              vals = vals.replaceFirst(/(?m)^\s*tag:\s*.*/, "  tag: ${env.GIT_SHA}")
            } else if (vals =~ /(?m)^\s*image:\s*$/) {
              vals = vals.replaceFirst(/(?m)^\s*image:\s*$/, "image:\n  tag: ${env.GIT_SHA}")
            } else if (!(vals =~ /(?m)^\s*image:/)) {
              vals += "\nimage:\n  tag: ${env.GIT_SHA}\n"
            }
            // עדכון repository
            if (vals =~ /(?m)^\s*repository:\s*.+/) {
              vals = vals.replaceFirst(/(?m)^\s*repository:\s*.*/, "  repository: ${env.IMAGE_REPO}")
            } else if (vals =~ /(?m)^\s*image:\s*$/) {
              vals = vals.replaceFirst(/(?m)^\s*image:\s*$/, "image:\n  repository: ${env.IMAGE_REPO}")
            } else if (!(vals =~ /(?m)^\s*image:/)) {
              vals += "\nimage:\n  repository: ${env.IMAGE_REPO}\n"
            }
            writeFile file: valuesPath, text: vals, encoding: 'UTF-8'
          }

          echo "Chart and values updated for ${env.GIT_SHA} -> ${newVersion}"
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
          def nodes = bat(returnStdout: true, script: "minikube -p ${env.MINIKUBE_PROFILE} kubectl -- get nodes --no-headers").trim()
          def apiStatus = bat(returnStatus: true, script: "minikube -p ${env.MINIKUBE_PROFILE} kubectl -- version --short")
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
