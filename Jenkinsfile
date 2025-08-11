// ---------- helpers (avoid CPS serialization issues) ----------
@NonCPS
String bumpPatch(String ver) {
  // e.g., "0.1.0" -> "0.1.1"
  def p = ver.trim().split('\\.')
  return "${p[0]}.${p[1]}.${(p[2] as int) + 1}"
}

@NonCPS
String bumpChartYaml(String chartYaml, String sha) {
  def out = []
  boolean appSet = false
  chartYaml.readLines().each { ln ->
    def t = ln.trim()
    if (t.startsWith('version:')) {
      def cur = t.split(':',2)[1].trim()
      out << "version: ${bumpPatch(cur)}"
    } else if (t.startsWith('appVersion:')) {
      out << "appVersion: \"${sha}\""
      appSet = true
    } else {
      out << ln
    }
  }
  if (!appSet) out << "appVersion: \"${sha}\""
  return out.join(System.lineSeparator())
}

@NonCPS
String upsertImageTag(String valuesYaml, String sha) {
  def m = (valuesYaml =~ /(?m)^\s*tag:/)
  if (m.find()) {
    return valuesYaml.replaceFirst(/(?m)^\s*tag:.*/, "  tag: \"${sha}\"")
  }
  return valuesYaml + System.lineSeparator() + "image:" +
         System.lineSeparator() + "  tag: \"${sha}\"" + System.lineSeparator()
}

// ------------------------ Pipeline ----------------------------
pipeline {
  agent any

  environment {
    APP_NAME      = 'flaskapp'
    HELM_DIR      = 'helm/flaskapp'
    PAGES_DIR     = 'docs'
    HELM_REPO_URL = 'https://azerez.github.io/devops0405-p3-Automation-CICD'
    REPO_SLUG     = 'azerez/devops0405-p3-Automation-CICD'

    // Docker image target (must match values.yaml)
    DOCKER_IMAGE  = 'erezazu/devops0405-docker-flask-app'

    GIT_NAME      = 'jenkins-ci'
    GIT_EMAIL     = 'ci@example.local'
  }

  options { timestamps() }

  stages {
    stage('Checkout SCM') {
      steps { checkout scm }
    }

    stage('Checkout') { steps { checkout scm } }

    stage('Init (capture SHA)') {
      steps {
        script {
          // Capture a clean short SHA (PowerShell trims the newline)
          env.GIT_SHA = powershell(returnStdout: true,
                                   script: '(git rev-parse --short HEAD).Trim()').trim()
        }
        echo "GIT_SHA = ${env.GIT_SHA}"
      }
    }

    stage('Helm Lint') {
      when { changeset pattern: 'helm/**', comparator: 'ANT' }
      steps { powershell "helm lint ${env.HELM_DIR}" }
    }

    stage('Bump Chart Version (patch)') {
      when {
        anyOf {
          changeset pattern: 'helm/**', comparator: 'ANT'
          changeset pattern: 'App/**',  comparator: 'ANT'
        }
      }
      steps {
        script {
          def chartPath = "${HELM_DIR}/Chart.yaml"
          def valsPath  = "${HELM_DIR}/values.yaml"
          def chartIn   = readFile(chartPath)
          def valsIn    = fileExists(valsPath) ? readFile(valsPath) : ""

          def chartOut  = bumpChartYaml(chartIn, env.GIT_SHA)
          def valsOut   = upsertImageTag(valsIn, env.GIT_SHA)

          writeFile file: chartPath, text: chartOut
          writeFile file: valsPath,  text: valsOut

          echo "Bumped Chart.yaml & values.yaml -> tag/appVersion = ${env.GIT_SHA}"
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
          helm package $env:HELM_DIR
          Move-Item "$env:HELM_DIR\\$env:APP_NAME-*.tgz" ".release\\" -Force
        '''
      }
    }

    stage('Publish to gh-pages') {
      when { changeset pattern: 'helm/**', comparator: 'ANT' }
      steps {
        withCredentials([string(credentialsId: 'github-token', variable: 'GHTOKEN')]) {
          bat """
            setlocal enableextensions
            for /f %%i in ('git rev-parse --abbrev-ref HEAD') do set CURR=%%i

            git config user.email "%GIT_EMAIL%"
            git config user.name  "%GIT_NAME%"

            git fetch origin gh-pages --depth=1 2>nul || echo no-remote
            git checkout -B gh-pages origin/gh-pages 2>nul || git checkout --orphan gh-pages

            mkdir "%PAGES_DIR%" 2>nul
            type nul > "%PAGES_DIR%\\.nojekyll"
            move /Y .release\\*.tgz "%PAGES_DIR%\\" >nul

            helm repo index "%PAGES_DIR%" --url %HELM_REPO_URL%

            git add "%PAGES_DIR%"
            git commit -m "publish chart %APP_NAME% %GIT_SHA%" 2>nul || echo nothing to commit

            git push "https://%GHTOKEN%@github.com/%REPO_SLUG%.git" gh-pages --force
            git checkout "%CURR%"
          """
        }
      }
    }

    stage('Build & Push Docker') {
      when { changeset pattern: 'App/**', comparator: 'ANT' }
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds',
                                          usernameVariable: 'DH_USER',
                                          passwordVariable: 'DH_PASS')]) {
          powershell """
            \$ErrorActionPreference = 'Stop'
            echo \$env:DH_PASS | docker login --username \$env:DH_USER --password-stdin
            docker build -t ${env.DOCKER_IMAGE}:${env.GIT_SHA} -f App/Dockerfile App
            docker push ${env.DOCKER_IMAGE}:${env.GIT_SHA}
          """
        }
      }
    }

    stage('Deploy to minikube') {
      // Run when Helm or the App changed (we produced a new image/tag)
      when {
        anyOf {
          changeset pattern: 'helm/**', comparator: 'ANT'
          changeset pattern: 'App/**',  comparator: 'ANT'
        }
      }
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONF')]) {
          powershell """
            \$ErrorActionPreference = 'Stop'
            \$env:KUBECONFIG = '${KUBECONF}'

            helm upgrade --install ${env.APP_NAME} ${env.HELM_DIR} `
              --namespace default --create-namespace `
              --set image.repository=${env.DOCKER_IMAGE} `
              --set image.tag=${env.GIT_SHA}

            kubectl -n default rollout status deploy/${env.APP_NAME} --timeout=120s
          """
        }
      }
    }
  }
}

