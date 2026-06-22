// Jenkinsfile - Pipeline CI/CD SentimentAI
pipeline {
    agent any // s’exécute sur n’importe quel agent disponible

    environment {
        IMAGE_NAME = 'sentiment-ai'
        REGISTRY   = 'ghcr.io/esistac' // remplacez VOTRE_PSEUDO
        IMAGE_TAG  = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
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
                    docker run --rm \\
                        --volumes-from jenkins \\
                        -w $WORKSPACE \\
                        python:3.12-slim \\
                        sh -c "pip install flake8 -q && flake8 src/ --max-line-length=100"
                '''
            }
        }

        // 2.4 Stage 3 - Build & Test
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
                    #Retourner le code de sortie des tests
                    exit $TEST_EXIT_CODE
                '''
            }
            post {
                failure { echo 'Tests échoués ou coverage insuffisant (< 70%)' }
            }
        }

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

        stage('Quality Gate') {
            steps {
                timeout(time: 15, unit: 'MINUTES') {
                    // Attend le résultat asynchrone du Quality Gate SonarQube
                    // abortPipeline: true => bloque Push et Deploy si le gate échoue
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        // Stage - Security Scan (Trivy)
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
                        docker tag \${IMAGE_NAME}:\${IMAGE_TAG} \${REGISTRY}/\${IMAGE_NAME}:\${IMAGE_TAG}
                        docker push \${REGISTRY}/\${IMAGE_NAME}:\${IMAGE_TAG}
                        docker tag \${IMAGE_NAME}:\${IMAGE_TAG} \${REGISTRY}/\${IMAGE_NAME}:latest
                        docker push \${REGISTRY}/\${IMAGE_NAME}:latest
                    """
                }
            }
        }

        // --- AJOUT TP4 : STAGES TERRAFORM ---
        stage('Terraform Init & Plan') {
            steps {
                dir('infra') {
                    // Initialisation
                    sh 'terraform init -no-color'
                    // Planification en passant le tag dynamique et le registre cible
                    sh "terraform plan -var='image_tag=${IMAGE_TAG}' -var='registry=${REGISTRY}' -no-color"
                }
            }
        }

        stage('Terraform Apply (Deploy Staging)') {
            steps {
                dir('infra') {
                    // Déploiement automatique
                    sh "terraform apply -var='image_tag=${IMAGE_TAG}' -var='registry=${REGISTRY}' -auto-approve -no-color"
                }
            }
        }

        // --- 4.2 AJOUT DU STAGE SMOKE TEST (11ème Stage) ---
        stage('Smoke Test') {
            steps {
                sh '''
                    echo "Attente démarrage (10s)..."
                    sleep 10

                    # 1. L’app répond (On utilise sentiment-staging sur le port interne 8000)
                    curl -f http://sentiment-staging:8000/health || exit 1
                    echo "/health OK"

                    # 2. Les métriques sont exposées
                    curl -s http://sentiment-staging:8000/metrics || exit 1
                    echo "/metrics OK"

                    # 3. Prometheus scrape l’app (On requête le conteneur prometheus sur le port 9090)
                    sleep 20 # attendre au moins 1 scrape (15s)
                    curl -s "http://prometheus:9090/api/v1/query?query=up{job='sentiment-ai'}" | \\
                        grep -q '"value":.*1' || exit 1
                    echo "Prometheus scrape sentiment-ai : UP"

                    # 4. Grafana répond (On requête le conteneur grafana sur le port 3000)
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

    post {
        always {
            // Nettoyer les conteneurs de test, qu’il y ait succès ou échec
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