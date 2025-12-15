FROM jenkins/jenkins:lts-jdk21

USER root

# Install Docker CLI
RUN curl -fsSL https://download.docker.com/linux/static/stable/x86_64/docker-24.0.7.tgz -o docker.tgz && \
    tar --extract --file docker.tgz --strip-components 1 --directory /usr/local/bin/ && \
    rm docker.tgz && \
    groupadd -f docker && \
    usermod -aG docker jenkins

USER jenkins