FROM jenkins/jenkins:lts-jdk21

USER root

# Install Docker CLI (latest version), kubectl, Helm, Buildx, and jq
RUN apt-get update && \
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        jq && \
    # =================================================================
    # Docker Installation
    # =================================================================
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    # Install Docker CLI and Buildx
    apt-get update && \
    apt-get install -y \
        docker-ce-cli \
        docker-buildx-plugin && \
    # =================================================================
    # kubectl Installation
    # =================================================================
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    rm kubectl && \
    # =================================================================
    # Helm Installation
    # =================================================================
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash && \
    # =================================================================
    # User Setup
    # =================================================================
    # Add jenkins to docker group
    groupadd -f docker && \
    usermod -aG docker jenkins && \
    # =================================================================
    # Cleanup
    # =================================================================
    rm -rf /var/lib/apt/lists/*

# Verify all installations
RUN echo "========================================" && \
    echo "✅ Installed versions:" && \
    docker --version && \
    kubectl version --client && \
    helm version && \
    jq --version && \
    echo "========================================"

USER jenkins