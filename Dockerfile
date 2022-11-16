FROM docker.io/rust:slim

# Set to noninteractive to fix issue with tzdate
ENV DEBIAN_FRONTEND=noninteractive
ENV LDFLAGS="-Wl,--no-as-needed"

# Set build march to native
ENV CFLAGS="-march=native -O3"
ENV CXXFLAGS="-march=native -O3"

# Build native for rust
ENV RUSTFLAGS="-Ctarget-cpu=native"

# Install Dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        pkg-config \
        git \
        curl \
        python3 \
        python3-pip \
        python3-setuptools \
        python3-wheel \
        doxygen \
        build-essential \
        cmake \
        libx265-dev \
        libnuma-dev \
        mercurial \
        ninja-build \
        nasm \
        yasm \
        parallel \
        jq \
        time \
        libavutil-dev \
        libavformat-dev \
        libavfilter-dev \
        libavdevice-dev \
        clang \
        libfontconfig-dev \
        bc && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir meson numpy

# Clone libvmaf
RUN git clone https://github.com/Netflix/vmaf.git /vmaf
WORKDIR /vmaf/libvmaf

# Checkout libvmaf version used by FFMPEG build
# Remove dynamic vmaf due to vmaf not matching actual build
#
RUN TAG=$(curl https://johnvansickle.com/ffmpeg/release-readme.txt 2>&1 | awk -F':' ' /libvmaf/ { print $2 }' | xargs) && \
    GITTAG=$(git tag | grep "$TAG") && \
    echo "Checking out $GITTAG" && \
    git checkout "tags/$GITTAG"

# Install libvmaf
RUN meson build --buildtype release && \
    ninja -vC build && \
    ninja -vC build install

# Install x265
RUN git clone https://github.com/videolan/x265.git /x265
WORKDIR /x265/build/linux
RUN chmod +x multilib.sh && \
    sed -i "s/-DLINKED_12BIT=ON/-DLINKED_12BIT=ON -DENABLE_SHARED=OFF/g" multilib.sh && \
    MAKEFLAGS="-j$(nproc)" ./multilib.sh && \
    cp 8bit/x265 /usr/local/bin && \
    cp 8bit/libx265.a /usr/local/lib

# Install aomenc
RUN git clone https://aomedia.googlesource.com/aom /aomenc && \
    mkdir -p /aom_build
WORKDIR /aom_build
RUN cmake -DBUILD_SHARED_LIBS=0 -DCMAKE_BUILD_TYPE=Release /aomenc && \
    make -j"$(nproc)" && \
    make install

RUN /usr/local/bin/aomenc --help

# Install rav1e
RUN git clone https://github.com/xiph/rav1e.git /rav1e
WORKDIR /rav1e
RUN cargo build --release && \
    cp /rav1e/target/release/rav1e /usr/local/bin

RUN  /usr/local/bin/rav1e --help

# Install svt-av1
RUN git clone https://gitlab.com/AOMediaCodec/SVT-AV1.git /svt-av1
WORKDIR /svt-av1/Build/linux/Release
RUN cmake -S /svt-av1/ -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_DEC=OFF && \
    cmake --build . --target install

RUN /usr/local/bin/SvtAv1EncApp --help

# Install Johnvansickle FFMPEG
WORKDIR /
RUN curl -LO https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz && \
    tar xf ffmpeg-* && \
    mv ffmpeg-*/* /usr/local/bin/

# Install ssimulacra2
RUN git clone https://github.com/rust-av/ssimulacra2_bin.git /ssimulacra2_bin
WORKDIR /ssimulacra2_bin
RUN cargo build --release && \
    cp target/release/ssimulacra2_rs /usr/local/bin


# Install dav1d
RUN git clone https://code.videolan.org/videolan/dav1d.git /dav1d
WORKDIR /dav1d
RUN meson build --default-library=static && \
    ninja -vC build && \
    ninja -vC build install

WORKDIR /app
COPY . /app

RUN chmod +x scripts/* && \
    pip3 install -r requirements.txt
