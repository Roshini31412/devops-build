pipeline {
    agent any

    environment {
        DOCKERHUB_USER        = "roshini31"
        IMAGE_BASE            = "devops-build"
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-creds')
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Determine target repo') {
            steps {
                script {
                    env.TARGET_REPO = (env.BRANCH_NAME == 'main' || env.BRANCH_NAME == 'master') ? 'prod' : 'dev'
                    env.IMAGE = "${DOCKERHUB_USER}/${IMAGE_BASE}-${env.TARGET_REPO}"
                }
            }
        }

        stage('Build image') {
            steps {
                sh "docker build -t ${IMAGE}:${BUILD_NUMBER} -t ${IMAGE}:latest ."
            }
        }

        stage('Push to Docker Hub') {
            steps {
                sh '''
                    echo "$DOCKERHUB_CREDENTIALS_PSW" | docker login -u "$DOCKERHUB_CREDENTIALS_USR" --password-stdin
                    docker push ${IMAGE}:${BUILD_NUMBER}
                    docker push ${IMAGE}:latest
                '''
            }
        }

        stage('Deploy') {
            steps {
                sh """
                    docker pull ${IMAGE}:latest
                    docker stop devops-build-app || true
                    docker rm devops-build-app || true
                    docker run -d --name devops-build-app -p 80:80 --restart unless-stopped ${IMAGE}:latest
                """
            }
        }
    }

    post {
        always {
            sh 'docker logout || true'
        }
        success {
            echo "Pipeline succeeded: ${IMAGE}:${BUILD_NUMBER} deployed."
        }
        failure {
            echo "Pipeline failed — check console output."
        }
    }
}
