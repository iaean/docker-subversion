#!/bin/bash
set -e

# return true if specified directory is empty
function directory_empty() {
  [ -n "$(find "${1}"/ -prune -empty)" ]
}

echo Running: "$@"

  BASE=/data/svn
  declare -A repos
  for r in ${SUBVERSION_REPOS} # No spaces allowed...
  do
    DIR=`echo ${r} | cut -s -d/ -f1`
    REP=`echo ${r} | cut -s -d/ -f2`
    if [[ -n ${DIR} && -n ${REP} && `basename ${r}` == "${REP}" ]]; then
      repos[${DIR}]+=" ${REP}"
      if [[ ! -d ${BASE}/${DIR}/${REP} ]]; then
        if [[ ! -d ${BASE}/${DIR} ]]; then
          mkdir -p ${BASE}/${DIR}
          ln -s ../.svn.access ${BASE}/${DIR}/.svn.access
          chown -R apache:apache ${BASE}/${DIR}

          current_desc=DESCRIPTION_${DIR}
          apache_snippet="<Location \"/svn/${DIR}\">\n  DAV svn\n  DavMinTimeout 300\n  SVNParentPath ${BASE}/${DIR}\n  SVNListParentPath on\n  SVNIndexXSLT /repos/.svnindex.xsl\n  AuthzSVNAccessFile ${BASE}/${DIR}/.svn.access\n</Location>\n"
          sed -i -e "s#// additional paths...#\$config->parentPath('${BASE}/${DIR}', '${!current_desc}');\n&#g" /var/www/html/include/config.php
          sed -i -e "s#^\# additional repo groups...#${apache_snippet}&#g" /etc/apache2/conf.d/svn.conf
        fi
        svnadmin create ${BASE}/${DIR}/${REP}
        chown -R apache:apache ${BASE}/${DIR}/${REP}
        echo "Repository ${BASE}/${DIR}/${REP} inside [${!current_desc}] created..."
      fi
    else
      echo "Skipping invalid: ${r}"
    fi
  done

  # for key in ${!repos[*]}; do
  #   # dynamicly making variable name
  #   current_desc=DESCRIPTION_$key
  #   for value in ${repos[$key]}; do
  #     # getting values
  #     echo "repo[$key] = $value (${!current_desc})"
  #   done
  # done

  if [[ -n $LDAP_BindDN && -n $LDAP_BindPW ]]; then
    LDAP_Use_TLS=${LDAP_Use_TLS:-no}
    LDAP_Use_TLS=${LDAP_Use_TLS,,}
    if [[ ${LDAP_Use_TLS} != "yes" ]]; then
      LDAP_Use_TLS=no
    fi

    if [[ -n $APACHE_LDAP_ALIAS && -n $APACHE_LDAP_URL ]]; then
      if [[ ${LDAP_Use_TLS} == "yes" ]]; then
        APACHE_LDAP_URL=`echo ${APACHE_LDAP_URL} | sed -e 's/^ldaps/ldap/'`
        APACHE_LDAP_URL="${APACHE_LDAP_URL} TLS"
      fi
      cat <<EOT >>/etc/apache2/conf.d/ldap.conf
<AuthnProviderAlias ldap ${APACHE_LDAP_ALIAS}>
  AuthLDAPURL ${APACHE_LDAP_URL}
  AuthLDAPBindDN ${LDAP_BindDN}
  AuthLDAPBindPassword ${LDAP_BindPW}
  AuthLDAPBindAuthoritative off
</AuthnProviderAlias>
EOT
      sed -i -e "s/AuthBasicProvider file/AuthBasicProvider file ${APACHE_LDAP_ALIAS}/g" /etc/apache2/conf.d/*.conf
    fi
    if [[ -n $SASL_LDAP_SERVER && -n $SASL_LDAP_SEARCHBASE && -n $SASL_LDAP_FILTER ]]; then
      if [[ ${LDAP_Use_TLS} == "yes" ]]; then
        SASL_LDAP_SERVER=`echo ${SASL_LDAP_SERVER} | sed -e 's/^ldaps/ldap/'`
      fi
      cat <<EOT >/etc/saslauthd.conf
ldap_servers: ${SASL_LDAP_SERVER}
ldap_bind_dn: ${LDAP_BindDN}
ldap_bind_pw: ${LDAP_BindPW}
ldap_search_base: ${SASL_LDAP_SEARCHBASE}
ldap_scope: sub
ldap_filter: ${SASL_LDAP_FILTER}
ldap_use_sasl: no
ldap_start_tls: ${LDAP_Use_TLS}
ldap_tls_cacert_file: /etc/ssl/cert.pem
ldap_tls_check_peer: no
# ldap_tls_ciphers: AES256-SHA:AES128-SHA
EOT
    fi
  fi

  /usr/sbin/saslauthd -m /var/run/saslauthd -a ldap -O /etc/saslauthd.conf -n 3
  sudo -u apache -g apache /usr/bin/svnserve -d -r ${BASE} --listen-port 3690 --config-file=/etc/subversion/svnserve.conf

  if [[ -n $SVN_LOCAL_ADMIN_USER && -n $SVN_LOCAL_ADMIN_PASS ]]; then
    echo "${SVN_LOCAL_ADMIN_PASS}" | saslpasswd2 -p -f /data/svn/.svn.sasldb -u "Local or LDAP Account" "${SVN_LOCAL_ADMIN_USER}"
    htpasswd -cmb /data/svn/.htpasswd "${SVN_LOCAL_ADMIN_USER}" "${SVN_LOCAL_ADMIN_PASS}"
  else
    touch/data/svn/.svn.sasldb
    touch /data/svn/.htpasswd
  fi
  chown -R apache:apache /data/svn/.svn.sasldb /data/svn/.htpasswd

if [[ `basename ${1}` == "httpd" ]]; then
  touch /var/log/apache2/error.log
  touch /var/log/apache2/subversion.log
  touch /var/log/apache2/access.log

  tail -f /var/log/apache2/error.log &
  tail -f /var/log/apache2/subversion.log &
  tail -f /var/log/apache2/access.log &

  exec "$@" </dev/null >/dev/null 2>&1
else
  httpd -k start
fi

exec "$@"

