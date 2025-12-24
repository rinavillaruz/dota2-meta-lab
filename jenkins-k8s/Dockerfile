FROM jenkins/jenkins:lts-jdk21

USER root

# Install Docker CLI, Buildx, and jq
RUN curl -fsSL https://download.docker.com/linux/static/stable/x86_64/docker-24.0.7.tgz -o docker.tgz && \
    tar --extract --file docker.tgz --strip-components 1 --directory /usr/local/bin/ && \
    rm docker.tgz && \
    groupadd -f docker && \
    usermod -aG docker jenkins && \
    # Install Docker Buildx plugin
    mkdir -p /usr/local/lib/docker/cli-plugins && \
    curl -SL https://github.com/docker/buildx/releases/download/v0.12.0/buildx-v0.12.0.linux-amd64 -o /usr/local/lib/docker/cli-plugins/docker-buildx && \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx && \
    # Install jq
    apt-get update && \
    apt-get install -y jq && \
    rm -rf /var/lib/apt/lists/*

USER jenkins