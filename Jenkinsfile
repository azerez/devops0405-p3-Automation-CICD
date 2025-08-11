pipeline {
  agent any

  environment {
    APP_NAME      = 'flaskapp'
    HELM_DIR      = 'helm/flaskapp'
    PAGES_DIR     = 'docs'
    // Public Helm repo URL (GitHub Pages) — NOTE: no trailing /docs
    HELM_REPO_URL = 'https://azerez.github.io/devops0405-p3-Automation-CICD'
    // GitHub owner/repo (used for pushing to gh-pages)
    REPO_SLUG     = 'azerez/devops0405-p3-Automation-CICD'
    GIT_NAME      = 'jenkins-ci'
    GIT_EMAIL     = 'ci@example.local'
  }

  options { timestamps() }

  stages {
    stage('Checkout') {
      steps {
        // Pull the branch/PR that triggered this build
        checkout scm
      }
    }

    stage('Helm Lint') {
      // Run only if something under "helm/**" changed
      when { changeset pattern: 'helm/**', comparator: 'ANT' }
      steps {
        // Validate Helm chart structure/templates
        sh "helm lint ${HELM_DIR}"
      }
    }

    stage('Bump Chart Version (patch)') {
      when { changeset pattern: 'helm/**', comparator: 'ANT' }
      steps {
        script {
          // Short commit SHA for traceability (used as appVersion/tag)
          env.GIT_SHA = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
        }
        sh """
          set -e
          CHART=${HELM_DIR}/Chart.yaml
          VALS=${HELM_DIR}/values.yaml

          # Read current chart version (SemVer: x.y.z) and bump the patch
          CUR_VER=$(awk '/^version:/{print $2}' "$CHART")
          MAJOR=\${CUR_VER%%.*}
          REST=\${CUR_VER#*.}
          MINOR=\${REST%%.*}
          PATCH=\${REST#*.}
          PATCH=\$((PATCH+1))
          NEW_VER="\$MAJOR.\$MINOR.\$PATCH"

          # Update 'version' in Chart.yaml
          awk -v nv="\$NEW_VER" '/^version:/{\$2=nv} {print}' "$CHART" > "$CHART.tmp" && mv "$CHART.tmp" "$CHART"

          # Update/append 'appVersion' in Chart.yaml to current Git SHA
          if grep -q '^appVersion:' "$CHART"; then
            awk -v av="${GIT_SHA}" '/^appVersion:/{\$2=av} {print}' "$CHART" > "$CHART.tmp" && mv "$CHART.tmp" "$CHART"
          else
            echo "appVersion: ${GIT_SHA}" >> "$CHART"
          fi

          # If values.yaml has 'tag:' under image, set it to the current Git SHA (best-effort)
          sed -i -E 's#(^\\s*tag:\\s*).+#\\1\"${GIT_SHA}\"#' "$VALS" || true

          echo "Bumped chart version to \$NEW_VER; image tag -> ${GIT_SHA}"
        """
      }
    }

    stage('Package Chart') {
      when { changeset pattern: 'helm/**', comparator: 'ANT' }
      steps {
        sh """
          set -e
          rm -rf .release
          mkdir -p .release
          cd ${HELM_DIR}
          # Create the .tgz package from the chart
          helm package .
          # Move the latest package to a staging folder at repo root
          mv ${APP_NAME}-*.tgz ../../.release/
        """
      }
    }

    stage('Publish to gh-pages') {
      when { changeset pattern: 'helm/**', comparator: 'ANT' }
      steps {
        // Use your GitHub PAT stored as Jenkins credential "github-token"
        withCredentials([string(credentialsId: 'github-token', variable: 'GHTOKEN')]) {
          sh """
            set -e
            CURR=\$(git rev-parse --abbrev-ref HEAD)

            # Configure Git identity for the commit
            git config user.email "${GIT_EMAIL}"
            git config user.name  "${GIT_NAME}"

            # Switch to gh-pages (create it orphaned if missing)
            git fetch origin gh-pages || true
            git checkout gh-pages || git checkout --orphan gh-pages

            # Ensure GitHub Pages folder exists and Jekyll is disabled
            mkdir -p ${PAGES_DIR}
            touch ${PAGES_DIR}/.nojekyll

            # Move packaged chart into docs/
            mv -f .release/*.tgz ${PAGES_DIR}/

            # Rebuild index.yaml with correct public URL (no /docs suffix)
            helm repo index ${PAGES_DIR} --url ${HELM_REPO_URL}

            # Commit and push to gh-pages using the PAT
            git add ${PAGES_DIR}
            git commit -m "publish chart ${APP_NAME} ${GIT_SHA}" || true
[O            git push https://${GHTOKEN}@github.com/${REPO_SLUG}.git gh-pages

            # Return to the original branch
            git checkout "\$CURR"
          """
        }
      }
    }
  }
}

