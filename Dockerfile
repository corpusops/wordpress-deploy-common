ARG WORDPRESS_FLAVOR=apache
ARG WORDPRESS_PHP_VER=5.6
ARG WORDPRESS_VER=4.9
ARG BASE=corpusops/wordpress:${WORDPRESS_VER}-php${WORDPRESS_PHP_VER}-${WORDPRESS_FLAVOR}
FROM $BASE
ARG WORDPRESS_FLAVOR=apache
ARG WORDPRESS_PHP_VER=5.6
ARG WORDPRESS_VER=4.9
ENV WORDPRESS_FLAVOR=$WORDPRESS_FLAVOR
ENV WORDPRESS_PHP_VER=$WORDPRESS_PHP_VER
ENV WORDPRESS_VER=$WORDPRESS_VER
ENV DEBIAN_FRONTEND=noninteractive
ARG TZ=Europe/Paris
ARG BUILD_DEV=y

# See https://github.com/nodejs/docker-node/issues/380
ARG GPG_KEYS=B42F6819007F00F88E364FD4036A9C25BF357DD4
ARG GPG_KEYS_SERVERS="hkp://p80.pool.sks-keyservers.net:80 hkp://ipv4.pool.sks-keyservers.net hkp://pgp.mit.edu:80"

WORKDIR /code
ADD apt.txt /code/apt.txt
# wordpress user is www-data or fpm user, switch back to root
USER root

# setup project timezone, dependencies, user & workdir, gosu
RUN bash -c 'set -ex \
    && : "set correct timezone" \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
    && : "install packages" \
    && apt-get update -qq \
    && apt-get install -qq -y $(grep -vE "^\s*#" /code/apt.txt  | tr "\n" " ") \
    && apt-get clean all && apt-get autoclean \
    && : no need in wordpress \
    && : "project user & workdir" \
    && : useradd -ms /bin/bash www-data --uid 1000'

ADD --chown=www-data:www-data public_html  /code/public_html
ADD                           sys          /code/sys
ADD         local/wordpress-deploy-common/ /code/local/wordpress-deploy-common/
# We make an intermediary init folder to allow to have the
# entrypoint mounted as a volume in dev
RUN bash -c 'set -ex \
    && cd /code && mkdir init \
    && find /code -type f -not -user www-data \
    | while read f;do chown www-data:www-data "$f";done \
    && cp -frnv /code/local/wordpress-deploy-common/public_html/* public_html \
    && cp -frnv /code/local/wordpress-deploy-common/sys/* sys \
    && cp -frnv sys/* init \
    && ln -sf $(pwd)/init/init.sh /init.sh \
    && gosu www-data:www-data bash -c "\
    : add extra deployment here"'

# image will drop privileges itself using gosu
CMD chmod 0644 /etc/cron.d/wordpress

WORKDIR /code/public_html

ENTRYPOINT []
CMD "/init.sh"
