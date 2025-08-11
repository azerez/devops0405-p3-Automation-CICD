pipeline {
  agent any
  options { skipDefaultCheckout(true) }

  environment {
    CHART_DIR   = 'helm/flaskapp'
    CHART_NAME  = 'flaskapp'
    RELEASE_DIR = '.release'

    // Docker image to build & push
    DOCKER_IMAGE = 'erezazu/devops0405-docker-flask-app'

    // GitHub repo & pages
    REPO_URL     = 'https://github.com/azerez/devops0405-p3-Automation-CICD.git'
    PAGES_URL    = 'https://azerez.github.io/devops0405-p3-Automation-CICD'
  }

  stages {
    stage('Checkout SCM') {
      steps { checkout scm }
    }

    stage('Init (capture SHA)') {
      steps {
        script {
          // Short git SHA for tagging chart + image
          env.GIT_SHA = bat(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
          echo "GIT_SHA = ${env.GIT_SHA}"
        }
      }
    }

    stage('Helm Lint') {
      steps {
        powershell """
          helm lint ${env.CHART_DIR}
        """
      }
    }

    stage('Bump Chart Version (patch)') {
      steps {
        script {
          bumpChartYaml("${env.CHART_DIR}/Chart.yaml",
                        "${env.CHART_DIR}/values.yaml",
                        env.GIT_SHA,
                        env.DOCKER_IMAGE)
        }
      }
    }

    stage('Package Chart') {
      steps {
        powershell """
          mkdir ${env.RELEASE_DIR} 2>$null | Out-Null
          helm package ${env.CHART_DIR} -d ${env.RELEASE_DIR}
        """
      }
    }

    stage('Publish to gh-pages') {
      steps {
        withCredentials([string(credentialsId: 'github-token', variable: 'GHTOKEN')]) {
          bat """
            git fetch origin gh-pages 2>NUL || ver > NUL
            git checkout -B gh-pages
            mkdir docs 2>NUL || ver > NUL
            move /Y ${env.RELEASE_DIR}\\*.tgz docs\\
          """
          // regenerate index.yaml
          powershell """
            helm repo index docs --url ${env.PAGES_URL}
          """
          bat """
            git add docs
            git -c user.name="jenkins-ci" -c user.email="jenkins@example.com" commit -m "publish chart ${env.GIT_SHA}" || ver > NUL
            git -c http.extraheader="AUTHORIZATION: bearer %GHTOKEN%" push ${env.REPO_URL} HEAD:gh-pages --force
          """
        }
      }
    }

    stage('Build & Push Docker') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds',
                                          usernameVariable: 'DOCKER_USER',
                                          passwordVariable: 'DOCKER_PASS')]) {
          bat """
            docker login -u %DOCKER_USER% -p %DOCKER_PASS%
            docker build -t ${env.DOCKER_IMAGE}:${env.GIT_SHA} App
            docker push ${env.DOCKER_IMAGE}:${env.GIT_SHA}
          """
        }
      }
    }

    stage('Deploy to minikube') {
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECFG')]) {
          withEnv(["KUBECONFIG=${KUBECFG}"]) {
            powershell """
              helm upgrade --install ${env.CHART_NAME} ${env.CHART_DIR} `
                --set image.repository=${env.DOCKER_IMAGE} `
                --set image.tag='${env.GIT_SHA}'
            """
          }
        }
      }
    }
  }

  post {
    always {
      stage('Declarative: Post Actions') {
        cleanWs()
      }
    }
  }
}

/**
 * Safely bump Chart.yaml (patch) + set appVersion=GIT_SHA
 * and make sure values.yaml contains the right repo and an empty tag.
 * Avoids non-serializable objects (no Matchers kept) and preserves valid YAML.
 */
def bumpChartYaml(String chartFile, String valuesFile, String gitSha, String dockerImage) {
  // ---- Chart.yaml ----
  String chart = readFile(chartFile)
  List<String> out = []
  boolean bumped = false
  boolean appSet = false

  chart.readLines().each { ln ->
    if (!bumped && ln.trim() ==~ /version:\s*\d+\.\d+\.\d+.*/) {
      def nums   = ln.replaceFirst(/.*version:\s*/, '').trim()
      def parts  = nums.tokenize('.')
      int patch  = (parts[2] as int) + 1
      out << "version: ${parts[0]}.${parts[1]}.${patch}"
      bumped = true
    } else if (!appSet && ln.trim().startsWith('appVersion:')) {
      out << "appVersion: \"${gitSha}\""
      appSet = true
    } else {
      out << ln
    }
  }
  if (!appSet) { out << "appVersion: \"${gitSha}\"" }
  writeFile file: chartFile, text: out.join('\n') + '\n'

  // ---- values.yaml ----
  String vals = readFile(valuesFile)
  List<String> vout = []
  vals.readLines().each { ln ->
    if (ln.trim().startsWith('repository:')) {
      // keep basic two-space indent that already exists in file
      vout << "  repository: ${dockerImage}"
    } else if (ln.trim().startsWith('tag:')) {
      vout << '  tag: ""'
    } else {
      vout << ln
    }
  }
  writeFile file: valuesFile, text: vout.join('\n') + '\n'

  echo "Chart and values updated for ${gitSha}"
}

