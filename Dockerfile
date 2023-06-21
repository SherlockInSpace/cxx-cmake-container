FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=America/Los_Angeles

# Enable add-apt-repository for below
RUN set -ex; \
    apt update;
#    apt install -y software-properties-common;

# Get the latest toolchain for the Ubuntu distribution
#RUN set -ex; \
#    add-apt-repository -y "ppa:ubuntu-toolchain-r/test";

# Install a bunch of devtools
RUN set -ex; \
    apt install -y \
        build-essential \
        cmake \
        curl \
        doxygen \
        gcovr \
        git \
        gcc-11 \
        g++-11 \
        graphviz \
        lcov \
        libgtest-dev \
        libssl-dev \
        ninja-build \
        ssh \
        sudo \
        vim \
        wget \
        zsh \
    ;

# Ensure the default is gcc-11
RUN set -ex; \
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 11; \
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 11; \
    update-alternatives --install /usr/bin/gcov gcov /usr/bin/gcov-11 11;

# Add our dev user
RUN set -ex; \
    useradd albedo -G sudo -m -d /home/albedo -s /usr/bin/zsh

# Ensure sudo group users are not 
# asked for a password when using 
# sudo command by ammending sudoers file
RUN set -ex; \
    echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Change user to albedo
USER albedo

# Get OhMyZsh
RUN set -ex; \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    
