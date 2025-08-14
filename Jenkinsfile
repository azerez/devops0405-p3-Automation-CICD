pipeline {
    agent any

    environment {
        DOCKER_IMAGE = "erezazu/devops0405-flaskapp"
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

        stage('Detect Helm Changes') {
            steps {
                script {
                    def changedFiles = sh(script: "git log -1 --name-only --pretty=format:''", returnStdout: true).trim().split("\n")
                    echo "Changed files:\n${changedFiles.join('\n')}"
                    HELM_CHANGED = changedFiles.any { it.contains("helm/flaskapp") }
                    echo "HELM_CHANGED = ${HELM_CHANGED}"
                }
            }
        }

        stage('Helm Lint') {
            when {
                expression { return HELM_CHANGED }
            }
            steps {
                dir('helm/flaskapp') {
                    sh 'helm lint .'
                }
            }
        }

        stage('Bump Chart Version (patch)') {
            when {
                expression { return HELM_CHANGED }
            }
            steps {
                dir('helm/flaskapp') {
                    script {
                        sh '''
                        version=$(grep '^version:' Chart.yaml | awk '{print $2}')
                        new_version=$(echo $version | awk -F. -v OFS=. '{$NF += 1 ; print}')
                        sed -i "s/^version:.*/version: $new_version/" Chart.yaml
                        '''
                    }
                }
            }
        }

        stage('Package Chart') {
            when {
                expression { return HELM_CHANGED }
            }
            steps {
                dir('helm/flaskapp') {
                    sh 'helm package .'
                }
            }
        }

        stage('Publish to gh-pages') {
            when {
                expression { return HELM_CHANGED }
            }
            steps {
                script {
                    sh '''
                    git config user.email "ci-bot@example.com"
                    git config user.name "ci-bot"
                    git worktree add gh-pages gh-pages
                    cp helm/flaskapp/*.tgz gh-pages/
                    cd gh-pages && git add . && git commit -m "Publish Helm chart" && git push origin gh-pages
                    '''
                }
            }
        }

        stage('Build & Push Docker') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKERHUB_USER', passwordVariable: 'DOCKERHUB_PASS')]) {
                    sh '''
                    docker login -u $DOCKERHUB_USER -p $DOCKERHUB_PASS
                    docker build -f App/Dockerfile -t ${DOCKER_IMAGE}:${GIT_SHA} App
                    docker push ${DOCKER_IMAGE}:${GIT_SHA}
                    '''
                }
            }
        }

        stage('Fetch kubeconfig from minikube') {
            steps {
                sh 'minikube update-context'
            }
        }

        stage('K8s Preflight') {
            steps {
                sh 'kubectl get nodes'
            }
        }

        stage('Deploy to minikube') {
            steps {
                sh '''
                helm upgrade --install flaskapp helm/flaskapp                     --set image.repository=${DOCKER_IMAGE}                     --set image.tag=${GIT_SHA}                     --namespace default --create-namespace
                '''
            }
        }

        stage('Smoke Test') {
            steps {
                sh 'kubectl get pods -n default'
            }
        }
    }
}
