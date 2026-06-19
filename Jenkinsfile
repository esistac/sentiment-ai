// Jenkinsfile - Pipeline CI/CD SentimentAI (Version Finale 8 Stages)
pipeline {
    agent any // s’exécute sur n’importe quel agent disponible
    
    environment {
        IMAGE_NAME = 'sentiment-ai'
        REGISTRY = 'ghcr.io/esistac' // remplacez VOTRE_PSEUDO
        IMAGE_TAG = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
    }
    
    stages {
        // Stage 1 - Checkout
        stage('Checkout') {
            steps {
                checkout scm
                echo "Branche : ${env.BRANCH_NAME}"
                echo "Commit  : ${env.GIT_COMMIT}"
                sh 'git log --oneline -5'
            }
        }

        // Stage 2 - Lint
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

        // Stage 3 - Build & Test
        stage ('Build & Test') {
            steps {
                sh '''
                    docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
                    # Supprimer un éventuel conteneur test-runner résiduel
                    docker rm -f test-runner 2>/dev/null || true
                    
                    # Lancer les tests en nommant le conteneur pour copier coverage.xml
                    set +e
                    docker run \
                        -e CI=true \
                        --name test-runner \
                        ${IMAGE_NAME}:${IMAGE_TAG} \
                        pytest tests/ -v \
                        --cov src \
                        --cov-report=xml:/tmp/coverage.xml \
                        --cov-report term-missing \
                        --cov-fail-under 70
                    TEST_EXIT_CODE=$?
                    set -e
                    
                    # Copier coverage.xml depuis le conteneur vers le workspace
                    docker cp test-runner:/tmp/coverage.xml ./coverage.xml 2>/dev/null || true
                    docker rm -f test-runner 2>/dev/null || true
                    
                    # Retourner le code de sortie des tests
                    exit $TEST_EXIT_CODE
                '''
            }
            post {
                failure { echo 'Tests échoués ou coverage insuffisant (< 70%)' }
            }
        }

        // Stage 4 - SonarQube Analysis
        stage ('SonarQube Analysis') {
            environment {
                SONARQUBE_TOKEN = credentials('sonar-token')
            }
            steps {
                withSonarQubeEnv('sonarqube') {
                    sh '''
                        # Accorder temporairement les droits d'écriture pour le conteneur scanner
                        chmod -R 777 "$WORKSPACE"

                        docker run --rm \
                            --network cicd-network \
                            --volumes-from jenkins \
                            -w "$WORKSPACE" \
                            -e SONAR_HOST_URL="$SONAR_HOST_URL" \
                            -e SONAR_TOKEN="$SONARQUBE_TOKEN" \
                            sonarsource/sonar-scanner-cli:latest \
                            sonar-scanner \
                            -Dsonar.projectKey=sentiment-ai \
                            -Dsonar.projectName=SentimentAI \
                            -Dsonar.projectBaseDir="$WORKSPACE" \
                            -Dsonar.sources=src \
                            -Dsonar.python.version=3.11 \
                            -Dsonar.python.coverage.reportPaths=coverage.xml \
                            -Dsonar.sourceEncoding=UTF-8 \
                            -Dsonar.scanner.metadataFilePath=$WORKSPACE/report-task.txt

                        # Restaurer des droits d'accès standards sécurisés
                        chmod -R 755 "$WORKSPACE"
                    '''
                }
            }
        }

        // Stage 5 - Quality Gate
        stage ('Quality Gate') {
            steps {
                timeout(time: 15, unit: 'MINUTES') {
                    // Attend le résultat asynchrone du Quality Gate SonarQube
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        // Stage 6 - Security Scan (Trivy)
        stage('Security Scan') {
            steps {
                sh '''
                    # Lancer le scan Trivy automatisé sur l'image générée au Stage 3
                    docker run --rm \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        -v trivy-cache:/root/.cache/trivy \
                        aquasec/trivy:latest image \
                        --severity HIGH,CRITICAL \
                        --exit-code 0 \
                        --format table \
                        ${IMAGE_NAME}:${IMAGE_TAG}
                '''
            }
            post {
                failure {
                    echo 'Vulnérabilités CRITICAL ou HIGH détectées !'
                    echo 'Corrigez les dépendances avant de déployer.'
                }
            }
        }

        // Stage 7 - Push
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
                        docker push \${REGISTRY}/\${IMAGE_NAME}:\${IMAGE_TAG}
                        docker tag \${IMAGE_NAME}:\${IMAGE_TAG} \${REGISTRY}/\${IMAGE_NAME}:latest
                        docker push \${REGISTRY}/\${IMAGE_NAME}:latest
                    """
                }
            }
        }
    
        // Stage 8 - Deploy Staging (Mis à jour selon l'énoncé de la partie 4.2)
        stage('Deploy Staging') {
            when { branch 'main' }
            steps {
                echo "Déploiement de ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} en staging"
                sh '''
                    # Arrêter le staging précédent proprement
                    docker compose -f docker-compose.yml -p staging down 2>/dev/null || true
                    # Démarrer la nouvelle version
                    docker compose -f docker-compose.yml -p staging up -d
                '''
                echo "Staging disponible sur http://localhost:8001"
            }
        }
    } // Fin de la section stages
        
    post {
        always {
            // Nettoyer les conteneurs de test, qu’il y ait succès ou échec
            sh 'docker compose down -v 2>/dev/null || true'
        }
        success {
            echo "Pipeline réussi ! Image : ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
        }
        failure {
            echo 'Pipeline échoué. Consultez les logs.'
        }
    }
}