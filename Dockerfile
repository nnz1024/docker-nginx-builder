FROM python:3.8-slim-buster AS builder

ARG NGINX_VERSION=1.18.0

ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && \
    apt-get install -y tzdata locales wget build-essential autogen automake autoconf \
    autotools-dev libreadline-dev libncurses5-dev libpcre3 libpcre3-dev libpng-dev \
    dh-make quilt lsb-release debhelper dpkg-dev dh-systemd pkg-config \
    zlib1g-dev libssl-dev openssl git  perl libtool tar unzip xutils-dev

# Set timezone and locale
ENV TZ Europe/Moscow
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
    && echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen && dpkg-reconfigure locales
ENV LANG en_US.UTF-8
ENV LC_CTYPE en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV LANGUAGE en_US.UTF-8

WORKDIR /nginx-builder
COPY builder /nginx-builder
RUN pip3 install -r requirements.txt 

# Config intentionally placed to separate cache level to prevent
# pip3 install re-runs in config change
COPY config.yaml /nginx-builder
RUN ./main.py build -f config.yaml -n ${NGINX_VERSION}

FROM debian:buster-slim

ARG NGINX_VERSION=1.18.0

COPY --from=builder /nginx-builder/nginx_${NGINX_VERSION}-1_amd64.deb /root

RUN set -x \
# create nginx user/group first, to be consistent throughout docker variants
    && addgroup --system --gid 101 nginx \
    && adduser --system --disabled-login --ingroup nginx --no-create-home --home /nonexistent --gecos "nginx user" --shell /bin/false --uid 101 nginx \
    && apt-get update \
    && apt-get install --no-install-recommends --no-install-suggests -y ca-certificates gettext-base curl /root/nginx_${NGINX_VERSION}-1_amd64.deb \
    && apt-get remove --purge --auto-remove -y && rm -rf /var/lib/apt/lists/* \
# forward request and error logs to docker log collector
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
# create a docker-entrypoint.d directory
    && mkdir /docker-entrypoint.d

COPY entrypoint /
ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 80

STOPSIGNAL SIGTERM

CMD ["nginx", "-g", "daemon off;"]
