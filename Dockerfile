# syntax=docker/dockerfile:1

# guacamole builder
FROM ghcr.io/linuxserver/baseimage-fedora:37 as guacbuilder

ARG GUACD_VERSION=1.1.0

RUN \
  echo "**** install build deps ****" && \
  dnf groupinstall -y \
    "Development Tools" && \
  dnf install -y \
    autoconf \
    automake \
    cairo-devel \
    CUnit-devel \
    freerdp-devel \
    libjpeg-turbo-devel \
    libpng-devel \
    libvorbis-devel \
    libwebp-devel \
    openssl-devel \
    perl \
    pulseaudio-libs-devel \
    uuid-devel \
    wget

RUN \
  echo "**** compile guacamole ****" && \
  mkdir /buildout && \
  mkdir /tmp/guac && \
  cd /tmp/guac && \
  wget \
    http://apache.org/dyn/closer.cgi?action=download\&filename=guacamole/${GUACD_VERSION}/source/guacamole-server-${GUACD_VERSION}.tar.gz \
    -O guac.tar.gz && \
  tar -xf guac.tar.gz && \
  cd guacamole-server-${GUACD_VERSION} && \
  ./configure \
    CPPFLAGS="-Wno-deprecated-declarations" \
    --disable-guacenc \
    --disable-guaclog \
    --prefix=/usr \
    --sysconfdir=/etc \
    --mandir=/usr/share/man \
    --localstatedir=/var \
    --enable-static \
    --with-libavcodec \
    --with-libavutil \
    --with-libswscale \
    --with-ssl \
    --without-winsock \
    --with-vorbis \
    --with-pulse \
    --without-pango \
    --without-terminal \
    --without-vnc \
    --with-rdp \
    --without-ssh \
    --without-telnet \
    --with-webp \
    --without-websockets && \
  make && \
  make DESTDIR=/buildout install

# nodejs builder
FROM ghcr.io/linuxserver/baseimage-fedora:37 as nodebuilder
ARG GCLIENT_RELEASE

RUN \
  echo "**** install build deps ****" && \
  dnf install -y \
    curl \
    nodejs \
    npm \
    pam-devel

RUN \
  echo "**** grab source ****" && \
  mkdir -p /gclient && \
  if [ -z ${GCLIENT_RELEASE+x} ]; then \
    GCLIENT_RELEASE=$(curl -sX GET "https://api.github.com/repos/linuxserver/gclient/releases/latest" \
    | awk '/tag_name/{print $4;exit}' FS='[""]'); \
  fi && \
  curl -o \
  /tmp/gclient.tar.gz -L \
    "https://github.com/linuxserver/gclient/archive/${GCLIENT_RELEASE}.tar.gz" && \
  tar xf \
  /tmp/gclient.tar.gz -C \
    /gclient/ --strip-components=1

RUN \
  echo "**** install node modules ****" && \
  cd /gclient && \
  npm install

# runtime stage
FROM ghcr.io/linuxserver/baseimage-rdesktop:fedora-37

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# Copy build outputs
COPY --from=nodebuilder /gclient /gclient
COPY --from=guacbuilder /buildout /

RUN \ 
  echo "**** install packages ****" && \
  dnf install -y --setopt=install_weak_deps=False --best \
    ca-certificates \
    freerdp-libs \
    nodejs \
    openbox \
    uuid && \
  echo "**** openbox tweaks ****" && \
  sed -i \
    's/NLIMC/NLMC/g' \
    /etc/xdg/openbox/rc.xml && \
  echo "**** cleanup ****" && \
  dnf autoremove -y && \
  dnf clean all && \
  rm -rf \
    /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000
VOLUME /config
