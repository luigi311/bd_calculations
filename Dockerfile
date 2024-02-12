FROM docker.io/library/archlinux:base-devel AS base

ENV LDFLAGS="-Wl,--no-as-needed"

# Set build march to native
ENV CFLAGS="-march=native -O3"
ENV CXXFLAGS="-march=native -O3"

# Build native for rust
ENV RUSTFLAGS="-Ctarget-cpu=native"

ENV BUILD_USER=makepkg

RUN sed -i 's/#MAKEFLAGS="-j2"/MAKEFLAGS="-j$(nproc)"/' /etc/makepkg.conf
RUN pacman-key --init && pacman -Sy --noconfirm archlinux-keyring && \
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

RUN useradd --system --create-home $BUILD_USER \
  && echo "$BUILD_USER ALL=(ALL:ALL) NOPASSWD:/usr/sbin/pacman" > /etc/sudoers.d/$BUILD_USER

USER $BUILD_USER
WORKDIR /home/$BUILD_USER

# Install yay
RUN git clone https://aur.archlinux.org/yay.git \
  && cd yay \
  && makepkg -sri --needed --noconfirm \
  && cd \
  && rm -rf .cache yay

# aom-git needs to be installed separately to resolve issues where aom-git 
# is installing the base encoders instead of the git verison.
# aom-git also installs aom which causes a package conflict requiring it to be ran twice.
# Generate hash commits prior to clearing out the cache from yay
RUN yay -Sy --batchinstall --noconfirm x265-git rav1e-git svt-av1-git && \
    yay -Sy --batchinstall --noconfirm aom-git || yes | yay -Sy --batchinstall aom-git && \
    yay -Sy --batchinstall --noconfirm ffmpeg-git && \
    cd ~/.cache/yay/x265-git/x265_git && git log --pretty=tformat:'%H' -n1 . > ~/x265 && \
    cd ~/.cache/yay/rav1e-git/rav1e && git log --pretty=tformat:'%H' -n1 . > ~/rav1e && \
    cd ~/.cache/yay/svt-av1-git/SVT-AV1 && git log --pretty=tformat:'%H' -n1 . > ~/svt-av1 && \
    cd ~/.cache/yay/aom-git/aom/ && git log --pretty=tformat:'%H' -n1 . > ~/aomenc && \
    yes | yay -Scc

USER root

# Move hash commits to root
RUN mv /home/makepkg/x265 /home/makepkg/rav1e /home/makepkg/svt-av1 /home/makepkg/aomenc / 

RUN pacman -Sy  --noconfirm \
        vapoursynth \
        ffms2  \
        mkvtoolnix-cli \
        vapoursynth-plugin-lsmashsource && \
    yes | pacman -Scc

# Test aomenc
RUN aomenc --help

# Test rav1e
RUN  rav1e --help

# Test svt-av1
RUN SvtAv1EncApp --help

# Install ssimulacra2
RUN git clone https://github.com/rust-av/ssimulacra2_bin.git /ssimulacra2_bin
WORKDIR /ssimulacra2_bin
RUN cargo build --release && \
    cp target/release/ssimulacra2_rs /usr/local/bin

WORKDIR /app
COPY . /app

RUN chmod +x scripts/*
    
ENV PATH="/opt/venv/bin:$PATH"

RUN python -m venv /opt/venv && \
    pip install -r requirements.txt
