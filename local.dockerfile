FROM ubuntu:18.04

LABEL maintainer="Connor Shride <connorshride2@gmail.com>" \
    readme.md="https://github.com/ConnorShride/box-ps" \
    description="This Dockerfile will install powershell and box-ps"

# Install dependencies besides powershell
RUN apt-get update \
    && apt-get install -y \
    apt-utils \
    # curl is required to grab the Linux package
    curl \
    # less is required for help in powershell
    less \
    # requied to setup the locale
    locales \
    # required for SSL
    ca-certificates \
    gss-ntlmssp \
    git \
    gnupg \
    gnupg2 \
    gnupg1

# install powershell
RUN curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - \
    && curl https://packages.microsoft.com/config/ubuntu/18.04/prod.list | tee /etc/apt/sources.list.d/microsoft.list \
    && apt-get update \
    && apt-get install -y powershell \
    && apt-get dist-upgrade -y \
    && locale-gen $LANG && update-locale

# install box-ps
COPY . /opt/box-ps

WORKDIR /opt/box-ps

CMD ["/bin/bash"]
