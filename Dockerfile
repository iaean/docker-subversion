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

# Install Apache with PHP, LDAP and DAV SVN
#
RUN apk add --no-cache apache2 apache2-webdav apache2-ldap apache2-ssl apache2-utils && \
    apk add --no-cache php7-xml php7-apache2 && \
    apk add --no-cache subversion mod_dav_svn && \
    apk add --no-cache sudo bash joe && \
    rm -f /etc/apache2/conf.d/info.conf \
          /etc/apache2/conf.d/languages.conf \
          /etc/apache2/conf.d/dav.conf \
          /etc/apache2/conf.d/ssl.conf \
          /etc/apache2/conf.d/userdir.conf && \
    mkdir /run/apache2 && \
    mkdir -p /data/svn/subversion && \
    mkdir -p /data/svn/sandbox

# RUN ln -sf /proc/self/fd/1 /var/log/apache2/access.log && \
#     ln -sf /proc/self/fd/1 /var/log/apache2/error.log

# Install WebSVN
#
WORKDIR /data/svn
RUN svnadmin create sandbox/test && \
    svnadmin create subversion/subversion && \
    svnadmin create subversion/websvn && \
    ln -s ../.svn.access sandbox/.svn.access && \
    ln -s ../.svn.access subversion/.svn.access && \
    #svnrdump -r HEAD dump https://svn.apache.org/repos/asf/subversion | svndumpfilter include trunk | svnadmin load subversion/subversion && \
    #svnrdump -r HEAD --username guest --password "" dump http://websvn.tigris.org/svn/websvn | svndumpfilter include trunk | svnadmin load subversion/websvn && \
    svnrdump -q -r HEAD dump https://svn.apache.org/repos/asf/subversion/trunk |\
      #sed -e 's/^Node-path:\ subversion\//Node-path:\ /g' |\
      #sed -e 's/^Node-copyfrom-path:\ subversion\//Node-copyfrom-path:\ /g' |\
      svnadmin -q load subversion/subversion && \
    svnrdump -q -r HEAD --username guest --password "" dump http://websvn.tigris.org/svn/websvn/trunk |\
      svnadmin -q load subversion/websvn && \
    svn cat file://localhost/data/svn/subversion/subversion/subversion/trunk/tools/xslt/svnindex.css > .svnindex.css && \
    svn cat file://localhost/data/svn/subversion/subversion/subversion/trunk/tools/xslt/svnindex.xsl > .svnindex.xsl && \
    sed -i 's/\/svnindex.css/\/repos\/.svnindex.css/' .svnindex.xsl

RUN svn export file://localhost/data/svn/subversion/websvn/trunk /var/www/html/ && \
    chown -R apache:apache /var/www/html/cache && \
    chmod -R 0700 /var/www/html/cache
    # svn export file://localhost/data/svn/subversion/websvn/trunk /var/www/localhost/htdocs/websvn && \
    # chown -R apache:apache /var/www/localhost/htdocs/websvn/cache && \
    # chmod -R 0700 /var/www/localhost/htdocs/websvn/cache

COPY htpasswd /data/svn/.htpasswd
COPY svnpasswd /data/svn/.svn.passwd
COPY svn.access /data/svn/.svn.access

COPY apache.conf/httpd.conf /etc/apache2/
COPY apache.conf/ldap.conf /etc/apache2/conf.d/
COPY apache.conf/svn.conf /etc/apache2/conf.d/
COPY apache.conf/websvn.conf /etc/apache2/conf.d/
COPY apache.conf/autoindex.conf /etc/apache2/conf.d/
COPY apache.conf/icons/* /var/www/localhost/icons/

COPY apache.conf/header.html /data/svn/.header.html
COPY apache.conf/footer.html /data/svn/.footer.html
COPY apache.conf/style.css /data/svn/.style.css

COPY websvn.conf /var/www/html/include/config.php
# COPY websvn.conf /var/www/localhost/htdocs/websvn/include/config.php

COPY svnserve.conf /etc/subversion/
COPY svnsasl.conf /etc/sasl2/

RUN chown -R apache:apache .

EXPOSE 80 3690
VOLUME ["/data/svn"]

COPY docker-entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/sbin/httpd", "-D", "FOREGROUND"]
