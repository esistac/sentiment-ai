// Jenkinsfile - Pipeline CI/CD SentimentAI
pipeline {
    agent any // s’exécute sur n’importe quel agent disponible

    environment {
        IMAGE_NAME = 'sentiment-ai'
        REGISTRY   = 'ghcr.io/esistac' // remplacez VOTRE_PSEUDO
        IMAGE_TAG  = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
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
                    docker run --rm \\
                        --volumes-from jenkins \\
                        -w $WORKSPACE \\
                        python:3.12-slim \\
                        sh -c "pip install flake8 -q && flake8 src/ --max-line-length=100"
                '''
            }
        }

        // Stage 3 - Build & Test
        stage('Build & Test') {
            steps {
                sh '''
                    docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
                    # Supprimer un éventuel conteneur test-runner résiduel
                    docker rm -f test-runner 2>/dev/null || true
                    # Lancer les tests en nommant le conteneur pour copier coverage.xml
                    set +e
                    docker run \\
                      -e CI=true \\
                      --name test-runner \\
                      ${IMAGE_NAME}:${IMAGE_TAG} \\
                      pytest tests/ -v \\
                      --cov src \\
                      --cov-report xml:/tmp/coverage.xml \\
                      --cov-report term-missing \\
                      --cov-fail-under=70
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
        stage('SonarQube Analysis') {
            environment {
                SONARQUBE_TOKEN = credentials('sonar-token')
            }
            steps {
                withSonarQubeEnv('sonarqube') {
                    sh '''
                        docker run --rm \\
                          --network cicd-network \\
                          --volumes-from jenkins \\
                          -w "$WORKSPACE" \\
                          -e SONAR_HOST_URL="$SONAR_HOST_URL" \\
                          -e SONAR_TOKEN="$SONARQUBE_TOKEN" \\
                          sonarsource/sonar-scanner-cli:latest \\
                          sonar-scanner \\
                          -Dsonar.projectKey=sentiment-ai \\
                          -Dsonar.projectName=SentimentAI \\
                          -Dsonar.projectBaseDir="$WORKSPACE" \\
                          -Dsonar.sources=src \\
                          -Dsonar.python.version=3.11 \\
                          -Dsonar.python.coverage.reportPaths=coverage.xml \\
                          -Dsonar.sourceEncoding=UTF-8 \\
                          -Dsonar.scanner.metadataFilePath=$WORKSPACE/report-task.txt
                    '''
                }
            }
        }

        // Stage 5 - Quality Gate
        stage('Quality Gate') {
            steps {
                timeout(time: 15, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        // Stage 6 - Security Scan (Trivy)
        stage('Security Scan (Trivy)') {
            steps {
                sh '''
                    # Lancer le scan Trivy automatisé sur l'image générée au Stage 3
                    docker run --rm \\
                        -v /var/run/docker.sock:/var/run/docker.sock \\
                        -v $WORKSPACE:/root/.cache/trivy \\
                        aquasec/trivy:latest image \\
                        --severity HIGH,CRITICAL \\
                        --exit-code 0 \\
                        --format table \\
                        ${IMAGE_NAME}:${IMAGE_TAG}
                '''
            }
        }

        // Stage 7 - Push (conditionnel)
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
                        docker tag \${IMAGE_NAME}:\${IMAGE_TAG} \${REGISTRY}/\${IMAGE_NAME}:\${IMAGE_TAG}
                        docker push \${REGISTRY}/\${IMAGE_NAME}:\${IMAGE_TAG}
                        docker tag \${IMAGE_NAME}:\${IMAGE_TAG} \${REGISTRY}/\${IMAGE_NAME}:latest
                        docker push \${REGISTRY}/\${IMAGE_NAME}:latest
                    """
                }
            }
        }

        // Stage 8 - Terraform Init & Plan
        stage('Terraform Init & Plan') {
            steps {
                dir('infra') {
                    sh 'terraform init -no-color'
                    sh "terraform plan -var='image_tag=${IMAGE_TAG}' -var='registry=${REGISTRY}' -no-color"
                }
            }
        }

        // Stage 9 - Terraform Apply (Deploy Staging)
        stage('Terraform Apply (Deploy Staging)') {
            steps {
                dir('infra') {
                    sh "terraform apply -var='image_tag=${IMAGE_TAG}' -var='registry=${REGISTRY}' -auto-approve -no-color"
                }
            }
        }

        // Stage 10 - Smoke Test
        stage('Smoke Test') {
            steps {
                sh '''
                    echo "Attente démarrage (10s)..."
                    sleep 10

                    # 1. L’app répond via l'alias réseau Docker
                    curl -f http://sentiment-staging:8000/health || exit 1
                    echo "/health OK"

                    # 2. Les métriques sont exposées
                    curl -s http://sentiment-staging:8000/metrics || true
                    echo "/metrics test exécuté"

                    # 3. Prometheus scrape l’app (Correction de l'URL d'API encodée)
                    sleep 10
                    curl -f "http://prometheus:9090/api/v1/query?query=up" || exit 1
                    echo "Prometheus accessible et fonctionnel"

                    # 4. Grafana répond
                    curl -f http://grafana:3000/api/health || exit 1
                    echo "Grafana OK"
                '''
            }
            post {
                failure {
                    sh 'docker logs prometheus || true'
                    sh 'docker logs sentiment-staging || true'
                    echo 'Smoke Test KO -- voir logs ci-dessus'
                }
            }
        }
    }

    post {
        always {
            sh 'docker compose down -v 2>/dev/null || true'
        }
        success {
            echo "Pipeline réussi ! L'infrastructure a été déployée proprement via Terraform."
        }
        failure {
            echo 'Pipeline échoué. Consultez les logs ci-dessus.'
        }
    }
}