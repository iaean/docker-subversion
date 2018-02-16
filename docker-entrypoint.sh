#!/bin/bash
set -e

# return true if specified directory is empty
function directory_empty() {
  [ -n "$(find "${1}"/ -prune -empty)" ]
}

echo Running: "$@"

if [[ `basename ${1}` == "httpd" ]]; then

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
    if [[ -n $APACHE_LDAP_ALIAS && -n $APACHE_LDAP_URL ]]; then
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
      cat <<EOT >/etc/saslauthd.conf
ldap_servers: ${SASL_LDAP_SERVER}
ldap_bind_dn: ${LDAP_BindDN}
ldap_bind_pw: ${LDAP_BindPW}
ldap_search_base: ${SASL_LDAP_SEARCHBASE}
ldap_scope: sub
ldap_filter: ${SASL_LDAP_FILTER}
ldap_use_sasl: no
ldap_tls_check_peer: no
ldap_tls_cacert_file: /etc/ssl/cert.pem
# ldap_start_tls: no
# ldap_tls_ciphers: HIGH:MEDIUM:-SSLv3
EOT
    fi
  fi

  touch /var/log/apache2/error.log
  touch /var/log/apache2/access.log

  tail -f /var/log/apache2/error.log &
  tail -f /var/log/apache2/access.log &

  /usr/sbin/saslauthd -m /var/run/saslauthd -a ldap -O /etc/saslauthd.conf -n 3
  sudo -u apache -g apache /usr/bin/svnserve -d -r ${BASE} --listen-port 3690 --config-file=/etc/subversion/svnserve.conf
  exec "$@" </dev/null 2>&1

fi

exec "$@"

