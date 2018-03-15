FROM alpine:latest

MAINTAINER Andreas Schulze <asl@iaean.net>

# Alpine cyrus-sasl doesn't support LDAP
#   https://pkgs.alpinelinux.org/package/edge/main/x86_64/cyrus-sasl
# Using building block from
#   https://github.com/dweomer/dockerfiles-saslauthd
#
ENV CYRUS_SASL_VERSION=2.1.26
RUN set -x && \
    mkdir -p /srv/saslauthd.d /tmp/cyrus-sasl /var/run/saslauthd && \
    export BUILD_DEPS="\
        autoconf automake make \
        curl \
        db-dev \
        g++ gcc \
        gzip \
        heimdal-dev \
        libtool \
        openldap-dev \
        tar" && \
    apk add --update ${BUILD_DEPS} cyrus-sasl libldap && \
    curl -fL ftp://ftp.cyrusimap.org/cyrus-sasl/cyrus-sasl-${CYRUS_SASL_VERSION}.tar.gz -o /tmp/cyrus-sasl.tgz && \
    curl -fL http://git.alpinelinux.org/cgit/aports/plain/main/cyrus-sasl/cyrus-sasl-2.1.25-avoid_pic_overwrite.patch?h=3.2-stable -o /tmp/cyrus-sasl-2.1.25-avoid_pic_overwrite.patch && \
    curl -fL http://git.alpinelinux.org/cgit/aports/plain/main/cyrus-sasl/cyrus-sasl-2.1.26-size_t.patch?h=3.2-stable -o /tmp/cyrus-sasl-2.1.26-size_t.patch && \
    curl -fL http://git.alpinelinux.org/cgit/aports/plain/main/cyrus-sasl/CVE-2013-4122.patch?h=3.2-stable -o /tmp/CVE-2013-4122.patch && \
    tar -xzf /tmp/cyrus-sasl.tgz --strip=1 -C /tmp/cyrus-sasl && \
    cd /tmp/cyrus-sasl && \
    patch -p1 -i /tmp/cyrus-sasl-2.1.25-avoid_pic_overwrite.patch || true && \
    patch -p1 -i /tmp/cyrus-sasl-2.1.26-size_t.patch || true && \
    patch -p1 -i /tmp/CVE-2013-4122.patch || true && \
    ./configure \
        --prefix=/usr \
        --sysconfdir=/etc \
        --localstatedir=/var \
        --disable-anon \
        --enable-cram \
        --enable-digest \
        --enable-ldapdb \
        --enable-login \
        --enable-ntlm \
        --disable-otp \
        --enable-plain \
        --with-gss_impl=heimdal \
        --with-devrandom=/dev/urandom \
        --with-ldap=/usr \
        --with-saslauthd=/var/run/saslauthd \
        --mandir=/usr/share/man && \
    make -j1 && \
    make -j1 install && \
    apk del --purge ${BUILD_DEPS} && \
    rm -fr /src /tmp/* /var/tmp/* /var/cache/apk/*

ENV SVN_BASE /data/svn

# Install Apache with PHP, LDAP and DAV SVN
#
RUN apk add --no-cache apache2 apache2-webdav apache2-ldap apache2-utils && \
    apk add --no-cache php7-xml php7-apache2 && \
    apk add --no-cache subversion mod_dav_svn && \
    apk add --no-cache sudo bash && \
    rm -f /etc/apache2/conf.d/info.conf \
          /etc/apache2/conf.d/languages.conf \
          /etc/apache2/conf.d/dav.conf \
          /etc/apache2/conf.d/ssl.conf \
          /etc/apache2/conf.d/userdir.conf && \
    mkdir /run/apache2

# Install WebSVN
#
ENV WEBSVN_VERSION=2.3.3
RUN svn --username guest --password "" export http://websvn.tigris.org/svn/websvn/tags/${WEBSVN_VERSION} /var/www/html/ && \
    chown -R apache:apache /var/www/html/cache && \
    chmod -R 0700 /var/www/html/cache

RUN mkdir -p /data/dist && \
    svn cat https://svn.apache.org/repos/asf/subversion/trunk/tools/xslt/svnindex.css > /data/dist/.svnindex.css && \
    svn cat https://svn.apache.org/repos/asf/subversion/trunk/tools/xslt/svnindex.xsl > /data/dist/.svnindex.xsl && \
    sed -i 's/\/svnindex.css/\/repos\/.svnindex.css/' /data/dist/.svnindex.xsl

RUN mkdir -p $SVN_BASE && \
    chown -R apache:apache $SVN_BASE
    # apk add --no-cache joe openldap-clients libressl

# Apache config
#
COPY apache.conf/httpd.conf /etc/apache2/
COPY apache.conf/conf.d/*.conf /etc/apache2/conf.d/
COPY apache.conf/icons/* /var/www/localhost/icons/

COPY apache.conf/header.html /data/dist/.header.html
COPY apache.conf/footer.html /data/dist/.footer.html
COPY apache.conf/style.css /data/dist/.style.css
COPY svn.access /data/dist/.svn.access

# WebSVN config
#
COPY websvn.conf /var/www/html/include/config.php
# COPY websvn.conf /var/www/localhost/htdocs/websvn/include/config.php

# SASL, LDAP, svnserve config
#
COPY svnserve.conf /etc/subversion/
COPY svnsasl.conf /etc/sasl2/svn.conf
COPY ldap.conf /etc/openldap/

COPY docker-entrypoint.sh /entrypoint.sh

WORKDIR $SVN_BASE
VOLUME $SVN_BASE

EXPOSE 80 3690
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/sbin/httpd", "-D", "FOREGROUND"]
