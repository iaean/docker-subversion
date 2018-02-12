FROM alpine:latest

MAINTAINER Andreas Schulze <asl@iaean.net>

RUN apk add --no-cache apache2 apache2-webdav apache2-ldap apache2-icons apache2-utils && \
    apk add --no-cache php7-xml php7-apache2 && \
    apk add --no-cache subversion mod_dav_svn cyrus-sasl && \
    apk add --no-cache bash joe && \
    rm -f /etc/apache2/conf.d/info.conf \
          /etc/apache2/conf.d/languages.conf \
          /etc/apache2/conf.d/dav.conf \
          /etc/apache2/conf.d/userdir.conf && \
    mkdir /etc/subversion && \
    mkdir /run/apache2 && \
    mkdir -p /data/svn/subversion && \
    mkdir -p /data/svn/sandbox

# RUN ln -sf /proc/self/fd/1 /var/log/apache2/access.log && \
#     ln -sf /proc/self/fd/1 /var/log/apache2/error.log

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
    sed -i 's/\/svnindex.css/\/repos\/.svnindex.css/' .svnindex.xsl && \
    chown -R apache:apache .

RUN svn export file://localhost/data/svn/subversion/websvn/trunk /var/www/html/ && \
    chown -R apache:apache /var/www/html/cache && \
    chmod -R 0700 /var/www/html/cache
    # svn export file://localhost/data/svn/subversion/websvn/trunk /var/www/localhost/htdocs/websvn && \
    # chown -R apache:apache /var/www/localhost/htdocs/websvn/cache && \
    # chmod -R 0700 /var/www/localhost/htdocs/websvn/cache

COPY htpasswd /data/svn/.htpasswd
COPY svn.access /data/svn/.svn.access
COPY apache.conf/httpd.conf /etc/apache2/
COPY apache.conf/ldap.conf /etc/apache2/conf.d/
COPY apache.conf/svn.conf /etc/apache2/conf.d/
COPY apache.conf/websvn.conf /etc/apache2/conf.d/
COPY websvn.conf /var/www/html/include/config.php
# COPY websvn.conf /var/www/localhost/htdocs/websvn/include/config.php

EXPOSE 80 3960
VOLUME ["/data/svn"]

COPY docker-entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/sbin/httpd", "-D", "FOREGROUND"]
