FROM quay.io/mhildenb/dev-demo-base:1.5

USER root

# Add the argocd cli
RUN curl -SL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')/argocd-linux-amd64 && \
    chmod +x /usr/local/bin/argocd

RUN curl -L http://mirror.openshift.com/pub/openshift-v4/clients/pipeline/0.17.2/tkn-linux-amd64-0.17.2.tar.gz | \
    tar -xvzf - -C /usr/local/bin/ tkn && chmod 755 /usr/local/bin/tkn

USER jboss

# this is done in the base image already (to support the demo shell images too), but for those that make
# local changes to .zshrc they should not have to rebuild the base
COPY .zshrc.example $HOME/.zshrc

ENV DEMO_HOME /workspaces/tekton-comparison-demo