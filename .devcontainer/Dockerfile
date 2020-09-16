FROM quay.io/mhildenb/dev-demo-base:1.1

USER root

# Add the argocd cli
RUN curl -SL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')/argocd-linux-amd64 && \
    chmod +x /usr/local/bin/argocd

USER jboss