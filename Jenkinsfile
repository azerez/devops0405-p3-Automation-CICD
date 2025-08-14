pipeline {
    agent any

    environment {
        APP_NAME = "flaskapp"
        CHART_PATH = "helm/${APP_NAME}"
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
                    GIT_SHA = bat(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    echo "GIT_SHA = ${GIT_SHA}"
                }
            }
        }

        stage('Helm Lint') {
            steps {
                dir("${CHART_PATH}") {
                    bat "helm lint ."
                }
            }
        }

        stage('Bump Chart Version (patch)') {
            steps {
                script {
                    def chartFile = readFile("${CHART_PATH}/Chart.yaml")
                    def valuesFile = readFile("${CHART_PATH}/values.yaml")
                    def newChart = chartFile.replaceAll(/version:.*/, "version: 0.1.${env.BUILD_NUMBER}")
                    def newValues = valuesFile.replaceAll(/tag:.*/, "tag: \"${GIT_SHA}\"")
                    writeFile file: "${CHART_PATH}/Chart.yaml", text: newChart
                    writeFile file: "${CHART_PATH}/values.yaml", text: newValues
                    echo "Chart and values updated for ${GIT_SHA}"
                }
            }
        }

        stage('Package Chart') {
            steps {
                bat "helm package -d .release ${CHART_PATH}"
            }
        }

        stage('Publish to gh-pages') {
            steps {
                bat """
                if not exist ghp mkdir ghp
                copy /Y .release\\*.tgz ghp\\ >NUL
                """
            }
        }

        stage('Build & Push Docker') {
            steps {
                script {
                    docker.build("erezazu/devops0405-docker-flask-app:${GIT_SHA}")
                          .push()
                }
            }
        }

        stage('Deploy to minikube') {
            steps {
                bat "helm upgrade --install ${APP_NAME} ${CHART_PATH} --namespace default"
            }
        }
    }
}