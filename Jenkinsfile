// Jenkinsfile — Declarative pipeline tuned to your credentials IDs
// Uses: docker-hub-creds (username+password or PAT), github-token (Secret text), kubeconfig (Kubeconfig file)

pipeline {
  agent any

  options {
    timestamps()
    skipDefaultCheckout(false)
  }

  parameters {
    booleanParam(name: 'FORCE_HELM_PUBLISH', defaultValue: false, description: 'Force bump/package/publish Helm even if no files under helm/ changed')
  }

  environment {
    // Docker image repo
    DOCKER_IMAGE   = 'docker.io/erezazu/devops0405-docker-flask-app'
    // Helm chart directory
    HELM_CHART_DIR = 'helm/flaskapp'
    // GitHub username for push-back
    GIT_USER = 'azerez'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Build Docker Image') {
      steps {
        script {
          env.GIT_SHORT = sh(returnStdout: true, script: 'git rev-parse --short=7 HEAD').trim()
        }
        echo "Building image: ${DOCKER_IMAGE}:${GIT_SHORT}"
        sh '''
          docker build -f App/Dockerfile -t ${DOCKER_IMAGE}:${GIT_SHORT} App
          docker tag ${DOCKER_IMAGE}:${GIT_SHORT} ${DOCKER_IMAGE}:latest
        '''
      }
    }

    stage('Push Docker Image') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds',
                                          usernameVariable: 'DH_USER',
                                          passwordVariable: 'DH_PASS')]) {
          sh '''
            echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin docker.io
            docker push ${DOCKER_IMAGE}:${GIT_SHORT}
            docker push ${DOCKER_IMAGE}:latest
          '''
        }
      }
    }

    stage('Helm Lint') {
      steps {
        sh "helm lint ${HELM_CHART_DIR}"
      }
    }

    stage('Helm Version Bump') {
      steps {
        sh '''
          set -e
          # Detect changes under helm/ in the last commit OR allow forcing via parameter
          if git diff --name-only HEAD~1..HEAD | grep -E '^helm/' >/dev/null 2>&1 || [ "${FORCE_HELM_PUBLISH}" = "true" ]; then
            CHART_FILE="${HELM_CHART_DIR}/Chart.yaml"
            [ -f "$CHART_FILE" ] || { echo "Chart file not found: $CHART_FILE"; exit 1; }

            CURR=$(grep '^version:' "$CHART_FILE" | awk '{print $2}')
            IFS=. read -r MA mi pa <<EOF
$CURR
EOF
            : "${pa:=0}"
            pa=$((pa+1))
            NEW="${MA}.${mi}.${pa}"

            sed -i "s/^version:.*/version: ${NEW}/" "$CHART_FILE"
            if grep -q '^appVersion:' "$CHART_FILE"; then
              sed -i "s/^appVersion:.*/appVersion: ${NEW}/" "$CHART_FILE"
            else
              echo "appVersion: ${NEW}" >> "$CHART_FILE"
            fi

            echo "Helm chart version bumped: ${CURR} -> ${NEW}"
            grep -E '^(version|appVersion):' "$CHART_FILE"
          else
            echo "No changes under helm/ and FORCE_HELM_PUBLISH=false — skipping bump."
          fi
        '''
      }
    }

    stage('Commit Helm Version to Git') {
      steps {
        sh '''
          # Commit only if files under helm/ changed or forced
          if git diff --name-only HEAD~1..HEAD | grep -E '^helm/' >/dev/null 2>&1 || [ "${FORCE_HELM_PUBLISH}" = "true" ]; then
            echo "Committing Chart.yaml back to main..."
          else
            echo "No helm changes — skipping commit."
            exit 0
          fi
        '''
        withCredentials([string(credentialsId: 'github-token', variable: 'GTOKEN')]) {
          sh '''
            set -e
            git config user.email "ci@azerez.local"
            git config user.name  "CI Bot"

            origin="$(git config --get remote.origin.url)"
            # Normalize to https and inject token
            origin="$(echo "$origin" | sed -E 's#^git@github.com:#https://github.com/#')"
            repo_path="$(echo "$origin" | sed -E 's#^https?://[^/]+/##; s#\.git$##')"
            origin_auth="https://${GIT_USER}:${GTOKEN}@github.com/${repo_path}.git"
            git remote set-url origin "$origin_auth"

            git add ${HELM_CHART_DIR}/Chart.yaml || true
            VER="$(grep '^version:' ${HELM_CHART_DIR}/Chart.yaml | awk '{print $2}')"
            git commit -m "ci(helm): bump chart to ${VER} [skip ci]" || true
            git push origin HEAD:main

            # restore remote
            git remote set-url origin "https://github.com/${repo_path}.git"
          '''
        }
      }
    }

    stage('Helm Package') {
      steps {
        sh '''
          if git diff --name-only HEAD~1..HEAD | grep -E '^helm/' >/dev/null 2>&1 || [ "${FORCE_HELM_PUBLISH}" = "true" ]; then
            set -e
            mkdir -p helm/dist
            helm package "${HELM_CHART_DIR}" -d helm/dist
            ls -l helm/dist
          else
            echo "No helm changes — skipping package."
          fi
        '''
        archiveArtifacts artifacts: 'helm/dist/*.tgz', fingerprint: true, allowEmptyArchive: true
      }
    }

    stage('Helm Publish-OCI') {
      steps {
        sh '''
          if git diff --name-only HEAD~1..HEAD | grep -E '^helm/' >/dev/null 2>&1 || [ "${FORCE_HELM_PUBLISH}" = "true" ]; then
            echo "Will publish Helm chart to OCI..."
          else
            echo "No helm changes — skipping publish."
            exit 0
          fi
        '''
        withCredentials([usernamePassword(credentialsId: 'docker-hub-creds',
                                          usernameVariable: 'DH_USER',
                                          passwordVariable: 'DH_PASS')]) {
          sh '''
            set -e
            helm registry login -u "$DH_USER" -p "$DH_PASS" registry-1.docker.io
            CHART_TGZ="$(ls -t helm/dist/*.tgz | head -n1)"
            echo "Pushing chart: $CHART_TGZ"
            helm push "$CHART_TGZ" oci://registry-1.docker.io/${DH_USER}
          '''
        }
      }
    }

    stage('Deploy to Kubernetes') {
      when { branch 'main' }
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KCFG')]) {
          sh '''
            set -e
            export KUBECONFIG="$KCFG"
            helm upgrade --install flaskapp "${HELM_CHART_DIR}"               --namespace dev --create-namespace               --set image.repository=${DOCKER_IMAGE}               --set image.tag=${GIT_SHORT}
          '''
        }
      }
    }

    // ----------------- TEST (health checks only + image run check) -----------------
    stage('TEST') {
      steps {
        echo '🔎 Verify Image Built (local)'
        sh '''
          set -e
          IMG_ID=$(docker images -q ${DOCKER_IMAGE}:${GIT_SHORT} || true)
          if [ -z "$IMG_ID" ]; then
            echo "❌ Image ${DOCKER_IMAGE}:${GIT_SHORT} not found locally"
            exit 1
          fi
          echo "✅ Local image exists: ${DOCKER_IMAGE}:${GIT_SHORT} ($IMG_ID)"
        '''

        echo '🔎 Verify Image Runs Successfully'
        sh '''
          set -e
          # מריץ את הקונטיינר עם פקודה פשוטה כדי לוודא שהאימג' runnable
          if ! docker run --rm ${DOCKER_IMAGE}:${GIT_SHORT} python --version >/dev/null 2>&1; then
            echo "❌ Image failed to run properly."
            exit 1
          fi
          echo "✅ Image ran successfully."
        '''

        echo '🔎 Verify Image In Registry (tags only)'
        sh '''
          set -e
          for TAG in ${GIT_SHORT} latest; do
            if ! docker manifest inspect ${DOCKER_IMAGE}:$TAG >/dev/null 2>&1; then
              echo "❌ Remote image tag not found: ${DOCKER_IMAGE}:$TAG"
              exit 1
            fi
            echo "✅ Remote image tag exists: ${DOCKER_IMAGE}:$TAG"
          done
        '''

        echo '🔎 Verify Chart Package (tgz exists)'
        sh '''
          set -e
          if ls -1 helm/dist/*.tgz >/dev/null 2>&1; then
            echo "✅ Chart package present in helm/dist:"
            ls -l helm/dist/*.tgz
          else
            echo "ℹ️ No chart package found (likely skipped due to no helm changes)"
          fi
        '''

        echo '🔎 Verify Rollout & Service Health (K8s)'
        script {
          if (env.BRANCH_NAME == 'main') {
            withCredentials([file(credentialsId: 'kubeconfig', variable: 'KCFG')]) {
              sh '''
                set -e
                export KUBECONFIG="$KCFG"

                # Verify rollout
                kubectl -n dev rollout status deploy/flaskapp --timeout=90s
                echo "✅ Deployment rollout completed."

                # Service health (in-cluster curl)
                SVC=$(kubectl -n dev get svc -l app.kubernetes.io/instance=flaskapp                       -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo "flaskapp")
                PORT=$(kubectl -n dev get svc "$SVC" -o jsonpath="{.spec.ports[0].port}")
                
                kubectl -n dev run curl-tester --rm -i --restart=Never --image=curlimages/curl:8.8.0 --                   -s -o /dev/null -w "%{http_code}" http://$SVC.dev.svc.cluster.local:$PORT/ > /tmp/http_code.txt

                CODE=$(cat /tmp/http_code.txt)
                if [ "$CODE" -ne 200 ]; then
                  echo "❌ Service health check failed (expected 200, got $CODE)."
                  exit 1
                fi
                echo "✅ Service health check passed (200)."
              '''
            }
          } else {
            echo 'ℹ️ Skipping K8s rollout & smoke test (branch not main).'
          }
        }
      }
    }
  }
}
