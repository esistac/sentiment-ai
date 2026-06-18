// Jenkinsfile - Pipeline CI/CD SentimentAI
pipeline {
    agent any // s’exécute sur n’importe quel agent disponible
    
    environment {
        IMAGE_NAME = 'sentiment-ai'
        REGISTRY = 'ghcr.io/esistac' // remplacez VOTRE_PSEUDO
        IMAGE_TAG = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
    }
    
    stages {
        // 2.2 Stage 1 - Checkout
        stage('Checkout') {
            steps {
                checkout scm
                echo "Branche : ${env.BRANCH_NAME}"
                echo "Commit  : ${env.GIT_COMMIT}"
                sh 'git log --oneline -5'
            }
        }

        // 2.3 Stage 2 - Lint
        stage('Lint') {
            steps {
                sh '''
                    docker run --rm \
                        --volumes-from jenkins \
                        -w $WORKSPACE \
                        python:3.12-slim \
                        sh -c "pip install flake8 -q && flake8 src/ --max-line-length=100"
                '''
            }
        }

        // 2.4 Stage 3 - Build & Test
        stage('Build & Test') {
            steps {
                sh "docker build -t \${IMAGE_NAME}:\${IMAGE_TAG} ."
                sh """
                    docker run --rm \\
                        \${IMAGE_NAME}:\${IMAGE_TAG} \\
                        pytest tests/ -v \\
                        --cov=src \\
                        --cov-report=xml:coverage.xml \\
                        --cov-report=term-missing \\
                        --cov-fail-under=70
                """
            }
            post {
                failure {
                    echo 'Tests échoués ou coverage insuffisant (< 70%)'
                }
            }
        }

        // 2.5 Stage 4 - Push (conditionnel)
        stage('Push') {
            when { branch 'main' }
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'github-token', 
                    usernameVariable: 'REGISTRY_USER', 
                    passwordVariable: 'REGISTRY_PASS'
                )]) {
                    sh """
                        echo \$REGISTRY_PASS | docker login ghcr.io -u \$REGISTRY_USER --password-stdin
                        docker push \${REGISTRY}/\${IMAGE_NAME}:\text{\${IMAGE_TAG}}
                        docker tag \text{\${IMAGE_NAME}}:\text{\${IMAGE_TAG}} \${REGISTRY}/\${IMAGE_NAME}:latest
                        docker push \${REGISTRY}/\${IMAGE_NAME}:latest
                    """
                }
            }
        }
    }
    
    post {
        always {
            // Nettoyer les conteneurs de test, qu’il y ait succès ou échec
            sh 'docker compose down -v 2>/dev/null || true'
        }
        success {
            echo "Pipeline réussi ! Image : ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
        }
        failure {
            echo 'Pipeline échoué. Consultez les logs ci-dessus.'
        }
    }
}