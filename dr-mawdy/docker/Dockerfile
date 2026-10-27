# Imagen "toolbox" para el runner de DR. NO PROBADA: ajustar versiones y repositorios internos.
# Construir y publicar en vuestro registro (ACR) y referenciarla en bitbucket-pipelines.yml.
FROM ubuntu:24.04
ARG TERRAFORM_VERSION=1.9.8
ENV DEBIAN_FRONTEND=noninteractive ACCEPT_EULA=Y

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg jq unzip git openssh-client netcat-openbsd \
      python3 python3-pip python3-venv shellcheck \
    && rm -rf /var/lib/apt/lists/*

# Azure CLI
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# PowerShell + sqlcmd (repositorio de Microsoft)
RUN curl -sSL -O https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb \
    && dpkg -i packages-microsoft-prod.deb && rm packages-microsoft-prod.deb \
    && apt-get update && apt-get install -y powershell mssql-tools18 unixodbc-dev \
    && rm -rf /var/lib/apt/lists/*
RUN pwsh -NoProfile -Command "Install-Module Az.Accounts,Az.RecoveryServices -Scope AllUsers -Force"
ENV PATH="$PATH:/opt/mssql-tools18/bin"

# Ansible y PyYAML
RUN pip3 install --break-system-packages ansible pyyaml

# Terraform
RUN curl -sSL -o /tmp/tf.zip https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    && unzip /tmp/tf.zip -d /usr/local/bin && rm /tmp/tf.zip
