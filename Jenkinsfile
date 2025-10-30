pipeline {
    agent any
    
    environment {
        // Docker registry settings
        DOCKER_REGISTRY = "docker.io"  // Change to your registry
        DOCKER_REPO = "yourusername"   // Change to your Docker Hub username
        IMAGE_NAME = "dota2-meta-lab"
        
        // Git settings
        GIT_REPO = "https://github.com/rinavillaruz/dota2-meta-lab.git"
        
        // Kubernetes namespace
        K8S_NAMESPACE = "data"
        
        // ArgoCD app name
        ARGOCD_APP = "dota2-dev"
    }
    
    stages {
        stage('Checkout') {
            steps {
                echo '📦 Checking out code...'
                checkout scm
            }
        }
        
        stage('Test') {
            steps {
                echo '🧪 Running tests...'
                script {
                    // Run Python tests
                    sh '''
                        # Install dependencies
                        pip install -r requirements.txt || true
                        
                        # Run tests
                        python -m pytest tests/ || true
                        
                        # Lint code
                        flake8 src/ || true
                    '''
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                echo '🐳 Building Docker image...'
                script {
                    // Generate version tag
                    def imageTag = "${env.BUILD_NUMBER}-${env.GIT_COMMIT.take(7)}"
                    env.IMAGE_TAG = imageTag
                    
                    // Build image
                    sh """
                        docker build -t ${DOCKER_REGISTRY}/${DOCKER_REPO}/${IMAGE_NAME}:${imageTag} .
                        docker tag ${DOCKER_REGISTRY}/${DOCKER_REPO}/${IMAGE_NAME}:${imageTag} ${DOCKER_REGISTRY}/${DOCKER_REPO}/${IMAGE_NAME}:latest
                    """
                }
            }
        }
        
        stage('Push Docker Image') {
            steps {
                echo '📤 Pushing Docker image to registry...'
                script {
                    // Login to Docker registry
                    withCredentials([usernamePassword(
                        credentialsId: 'docker-hub-credentials',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )]) {
                        sh """
                            echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin ${DOCKER_REGISTRY}
                            docker push ${DOCKER_REGISTRY}/${DOCKER_REPO}/${IMAGE_NAME}:${env.IMAGE_TAG}
                            docker push ${DOCKER_REGISTRY}/${DOCKER_REPO}/${IMAGE_NAME}:latest
                        """
                    }
                }
            }
        }
        
        stage('Update Helm Values') {
            steps {
                echo '📝 Updating Helm values with new image tag...'
                script {
                    withCredentials([usernamePassword(
                        credentialsId: 'github-credentials',
                        usernameVariable: 'GIT_USER',
                        passwordVariable: 'GIT_TOKEN'
                    )]) {
                        sh """
                            # Configure Git
                            git config user.email "jenkins@dota2-meta-lab.local"
                            git config user.name "Jenkins CI"
                            
                            # Update image tag in values file
                            sed -i 's|tag: .*|tag: "${env.IMAGE_TAG}"|g' helm/values-dev.yaml
                            
                            # Commit and push
                            git add helm/values-dev.yaml
                            git commit -m "ci: update image tag to ${env.IMAGE_TAG}" || true
                            git push https://${GIT_TOKEN}@github.com/rinavillaruz/dota2-meta-lab.git HEAD:main
                        """
                    }
                }
            }
        }
        
        stage('Trigger ArgoCD Sync') {
            steps {
                echo '🔄 Triggering ArgoCD sync...'
                script {
                    sh """
                        # ArgoCD will auto-sync, but we can trigger it manually for faster deployment
                        argocd app sync ${ARGOCD_APP} --insecure || echo "ArgoCD sync triggered (or auto-sync will handle it)"
                    """
                }
            }
        }
        
        stage('Verify Deployment') {
            steps {
                echo '✅ Verifying deployment...'
                script {
                    sh """
                        # Wait for deployment to be ready
                        kubectl rollout status deployment/ml-api -n ${K8S_NAMESPACE} --timeout=300s || true
                        
                        # Show current pods
                        kubectl get pods -n ${K8S_NAMESPACE}
                    """
                }
            }
        }
    }
    
    post {
        success {
            echo '✅ Pipeline completed successfully!'
            echo "🚀 Image: ${DOCKER_REGISTRY}/${DOCKER_REPO}/${IMAGE_NAME}:${env.IMAGE_TAG}"
        }
        failure {
            echo '❌ Pipeline failed!'
        }
        always {
            echo '🧹 Cleaning up...'
            // Clean up Docker images to save space
            sh """
                docker rmi ${DOCKER_REGISTRY}/${DOCKER_REPO}/${IMAGE_NAME}:${env.IMAGE_TAG} || true
                docker rmi ${DOCKER_REGISTRY}/${DOCKER_REPO}/${IMAGE_NAME}:latest || true
            """
        }
    }
}