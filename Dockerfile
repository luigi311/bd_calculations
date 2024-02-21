FROM shssoichiro/av1an-ci:latest AS base

ENV LDFLAGS="-Wl,--no-as-needed"

# Set build march to native
ENV CFLAGS="-march=native -O3"
ENV CXXFLAGS="-march=native -O3"

# Build native for rust
ENV RUSTFLAGS="-Ctarget-cpu=native"

ENV BUILD_USER=user

RUN sed -i 's/#MAKEFLAGS="-j2"/MAKEFLAGS="-j$(nproc)"/' /etc/makepkg.conf
RUN pacman-key --init && pacman -Syu --noconfirm archlinux-keyring && \
    pacman -Syu --noconfirm \
        wget \
        dos2unix \
        git \
        openssl \
        unzip \
        python-pip \
        parallel \
        jq \
        time \
        bc && \
    yes | pacman -Scc

USER $BUILD_USER

# Install ffmpeg-git seperate in case of failure
RUN yes | yay -Sy --batchinstall ffmpeg-git && \
    yes | yay -Scc

# aom-git needs to be installed separately to resolve issues where aom-git 
# is installing the base encoders instead of the git verison.
# aom-git also installs aom which causes a package conflict requiring it to be ran twice.
# Generate hash commits prior to clearing out the cache from yay
RUN yay -Sy --batchinstall --noconfirm x264-git x265-git rav1e-git svt-av1-git && \
    yay -S --batchinstall --noconfirm aom-git || yes | yay -Sy --batchinstall aom-git && \
    yay -S --batchinstall --noconfirm ssimulacra2_bin-git && \
    yay -S --batchinstall --noconfirm vvenc-git vvc-vtm  && \
    cd ~/.cache/yay/x264-git/x264 && git log --pretty=tformat:'%H' -n1 . > ~/x264 && \
    cd ~/.cache/yay/x265-git/x265_git && git log --pretty=tformat:'%H' -n1 . > ~/x265 && \
    cd ~/.cache/yay/rav1e-git/rav1e && git log --pretty=tformat:'%H' -n1 . > ~/rav1e && \
    cd ~/.cache/yay/svt-av1-git/SVT-AV1 && git log --pretty=tformat:'%H' -n1 . > ~/svt-av1 && \
    cd ~/.cache/yay/aom-git/aom/ && git log --pretty=tformat:'%H' -n1 . > ~/aomenc && \
    cd ~/.cache/yay/vvenc-git/vvenc && git log --pretty=tformat:'%H' -n1 . > ~/vvencapp && \
    yes | yay -Scc

USER root

# Move hash commits to root
RUN mv "/home/${BUILD_USER}/x264" \
    "/home/${BUILD_USER}/x265" \
    "/home/${BUILD_USER}/rav1e" \
    "/home/${BUILD_USER}/svt-av1" \
    "/home/${BUILD_USER}/aomenc" \
    "/home/${BUILD_USER}/vvencapp" \
    /

# Test aomenc
RUN aomenc --help

# Test rav1e
RUN  rav1e --help

# Test svt-av1
RUN SvtAv1EncApp --help

# Test vvenc
RUN vvencapp --help

WORKDIR /app
COPY . /app

RUN chmod +x scripts/*
    
ENV PATH="/opt/venv/bin:$PATH"

RUN python -m venv /opt/venv && \
    pip install -r requirements.txt
