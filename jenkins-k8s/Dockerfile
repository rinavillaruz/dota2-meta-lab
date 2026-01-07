FROM jenkins/jenkins:lts-jdk21

USER root

# Install Docker CLI (latest version), Buildx, and jq
RUN apt-get update && \
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        jq && \
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
    # Add jenkins to docker group
    groupadd -f docker && \
    usermod -aG docker jenkins && \
    # Clean up
    rm -rf /var/lib/apt/lists/*

USER jenkins