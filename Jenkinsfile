pipeline {
    agent any

    environment {
        APP_NAME = "flaskapp"
        K8S_NAMESPACE = "default"
        HEALTH_PATH = "/health"
        DOCKER_IMAGE = "erezazu/devops0405-docker-flask-app"
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
                    GIT_SHA = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
                    echo "GIT_SHA = ${GIT_SHA}"
                }
            }
        }

        stage('Helm Lint') {
            steps {
                dir('helm/flaskapp') {
                    sh 'helm lint .'
                }
            }
        }

        stage('Bump Chart Version (patch)') {
            steps {
                script {
                    def chartFile = readFile('helm/flaskapp/Chart.yaml')
                    def versionMatch = (chartFile =~ /version: (\d+\.\d+\.)(\d+)/)
                    if (versionMatch) {
                        def prefix = versionMatch[0][1]
                        def patch = versionMatch[0][2].toInteger() + 1
                        chartFile = chartFile.replaceFirst(/version: .*/, "version: ${prefix}${patch}")
                        writeFile file: 'helm/flaskapp/Chart.yaml', text: chartFile
                        echo "Chart version bumped to ${prefix}${patch}"
                    }
                    def valuesFile = readFile('helm/flaskapp/values.yaml')
                    valuesFile = valuesFile.replaceFirst(/tag: .*/, "tag: \"${GIT_SHA}\"")
                    writeFile file: 'helm/flaskapp/values.yaml', text: valuesFile
                }
            }
        }

        stage('Package Chart') {
            steps {
                sh 'helm package -d .release helm/flaskapp'
            }
        }

        stage('Publish to gh-pages') {
            steps {
                sh '''
                    mkdir -p ghp
                    cp .release/*.tgz ghp/
                '''
            }
        }

        stage('Build & Push Docker') {
            steps {
                script {
                    docker.build("${DOCKER_IMAGE}:${GIT_SHA}")
                    docker.withRegistry('', 'dockerhub-credentials') {
                        docker.image("${DOCKER_IMAGE}:${GIT_SHA}").push()
                        docker.image("${DOCKER_IMAGE}:${GIT_SHA}").push("latest")
                    }
                }
            }
        }

        stage('Deploy to minikube') {
            steps {
                sh '''
                    helm upgrade --install ${APP_NAME} helm/flaskapp                       --namespace ${K8S_NAMESPACE}                       --set image.tag=${GIT_SHA}
                '''
            }
        }

        stage('Smoke Test') {
            steps {
                sh '''
                    set -e
                    if ! kubectl -n ${K8S_NAMESPACE} rollout status deploy/${APP_NAME} --timeout=300s; then
                        echo "Rollout did not complete in time — collecting diagnostics..."
                        kubectl -n ${K8S_NAMESPACE} get pods -l app=${APP_NAME} -o wide || true
                        kubectl -n ${K8S_NAMESPACE} describe deploy/${APP_NAME} || true
                        kubectl -n ${K8S_NAMESPACE} describe rs -l app=${APP_NAME} || true
                        kubectl -n ${K8S_NAMESPACE} logs --tail=200 -l app=${APP_NAME} --all-containers=true || true
                        exit 1
                    fi

                    NODEPORT=$(kubectl -n ${K8S_NAMESPACE} get svc ${APP_NAME} -o jsonpath="{.spec.ports[0].nodePort}")
                    IP=$(minikube ip)
                    echo "Probing http://${IP}:${NODEPORT}${HEALTH_PATH} ..."
                    for i in $(seq 1 30); do
                        if curl -fsS "http://${IP}:${NODEPORT}${HEALTH_PATH}"; then
                            echo "Smoke test OK"
                            exit 0
                        fi
                        sleep 2
                    done
                    echo "Smoke test FAILED"
                    exit 1
                '''
            }
        }
    }
}