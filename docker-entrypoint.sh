#!/bin/bash
set -e

# return true if specified directory is empty
function directory_empty() {
  [ -n "$(find "${1}"/ -prune -empty)" ]
}

echo Running: "$@"

###
### Empty bind mount volume bootstrapping...
###

find /data/dist -type f -name '.*' -exec mv -n {} /data/svn \;

###
### Repository bootstrapping...
###

# default repo
if [[ -z "${SUBVERSION_REPOS}" ]]; then
  SUBVERSION_REPOS=sandbox/test
  DESCRIPTION_sandbox='Sandbox and Testbed'
  cat <<EOT >>/data/svn/.svn.access

[test:/]
* = rw
EOT
fi

declare -A repos
OIFS=$IFS
IFS=';' read -a TOKEN <<< "${SUBVERSION_REPOS}"
for r in "${TOKEN[@]}"
do
  DIR=`echo ${r} | cut -s -d/ -f1 | sed 's/\s/_/g'`
  REP=`echo ${r} | cut -s -d/ -f2 | sed 's/\s/_/g'`
  if [[ -n ${DIR} && -n ${REP} && `basename "${r}"` == "${REP}" ]]; then
    repos[${DIR}]+=" ${REP}"
    # dynamicly making variable name
    current_desc=DESCRIPTION_"${DIR}"
    current_desc=${!current_desc:-'Unlabeled repository group'}
    if [[ ! -d ${SVN_BASE}/${DIR}/${REP} ]]; then
      if [[ ! -d ${SVN_BASE}/${DIR} ]]; then
        mkdir -p ${SVN_BASE}/${DIR}
        ln -s ../.svn.access ${SVN_BASE}/${DIR}/.svn.access
        chown -R apache:apache ${SVN_BASE}/${DIR}
      fi
      svnadmin create ${SVN_BASE}/${DIR}/${REP}
      chown -R apache:apache ${SVN_BASE}/${DIR}/${REP}
      echo "Repository ${SVN_BASE}/${DIR}/${REP} inside group '${current_desc}' created..."
    fi
  else
    echo "Skipping invalid: ${r}"
  fi
done
IFS=$OIFS

for key in ${!repos[*]}; do
  # for value in ${repos[$key]}; do
  #   # getting values
  #   echo "repo[$key] = $value (${!current_desc})"
  # done

  current_desc=DESCRIPTION_${key}
  # Uncomment and use ${current_desc} instead of ${!current_desc}
  # gives another flavor in WebSVN for undefined parent directories... 
  # current_desc=${!current_desc:-'Unlabeled repository group'}

  apache_snippet="<Location \"/svn/${key}\">\n  DAV svn\n  DavMinTimeout 300\n  SVNParentPath ${SVN_BASE}/${key}\n  SVNListParentPath on\n  SVNIndexXSLT /repos/.svnindex.xsl\n  AuthzSVNAccessFile ${SVN_BASE}/${key}/.svn.access\n</Location>\n"
  sed -i -e "s#// additional paths...#\$config->parentPath('${SVN_BASE}/${key}', '${!current_desc}');\n&#g" /var/www/html/include/config.php
  sed -i -e "s#^\# additional repo groups...#${apache_snippet}&#g" /etc/apache2/conf.d/svn.conf
done

###
### LDAP bootstrapping...
###

if [[ -n $LDAP_BindDN && -n $LDAP_BindPW ]]; then
  # Secure LDAP stuff
  LDAP_Use_TLS=${LDAP_Use_TLS:-no}
  LDAP_Use_TLS=${LDAP_Use_TLS,,}
  if [[ ${LDAP_Use_TLS} != "yes" ]]; then
    LDAP_Use_TLS=no
  fi
  LDAP_TLS_VerifyCert=${LDAP_TLS_VerifyCert:-allow}
  echo "tls_reqcert ${LDAP_TLS_VerifyCert}" >>/etc/openldap/ldap.conf
  if [[ -n $LDAP_TLS_Ciphers ]]; then
    echo "tls_cipher_suite ${LDAP_TLS_Ciphers}" >>/etc/openldap/ldap.conf
  fi

  # Apache LDAP
  APACHE_LDAP_ALIAS=${APACHE_LDAP_ALIAS:-directory}
  if [[ -n $APACHE_LDAP_URL ]]; then
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

  # SASL LDAP
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
EOT
  fi
fi

###
### Local SASL/htpasswd bootstrapping...
###

# Create .htpasswd and .svn.sasldb
if [[ ! -f /data/svn/.htpasswd ]]; then
  touch /data/svn/.htpasswd
fi
if [[ ! -f /data/svn/.svn.sasldb ]]; then
  echo "bootstrap" | \
  saslpasswd2 -p -f /data/svn/.svn.sasldb bootstrap
  saslpasswd2 -d -f /data/svn/.svn.sasldb bootstrap
fi
# Create or update USER
if [[ -n $SVN_LOCAL_ADMIN_USER && -n $SVN_LOCAL_ADMIN_PASS ]]; then
  echo "${SVN_LOCAL_ADMIN_PASS}" | saslpasswd2 \
    -p -f /data/svn/.svn.sasldb \
    -u "Local or LDAP Account" "${SVN_LOCAL_ADMIN_USER}"
  htpasswd -mb /data/svn/.htpasswd "${SVN_LOCAL_ADMIN_USER}" \
    "${SVN_LOCAL_ADMIN_PASS}" >/dev/null 2>&1
  sed -i -e "s/^# %%LOCAL_ADMIN%%/${SVN_LOCAL_ADMIN_USER}/" /data/svn/.svn.access
fi

find /data/svn -type f -name '.*' -exec chown apache:apache {} \;

###
### Start SASL/SVN services...
###

/usr/sbin/saslauthd -m /var/run/saslauthd -a ldap -O /etc/saslauthd.conf -n 3
sudo -u apache -g apache /usr/bin/svnserve -d -r ${SVN_BASE} \
  --listen-port 3690 --config-file=/etc/subversion/svnserve.conf

###
### Start apache...
###

if [[ `basename ${1}` == "httpd" ]]; then # prod
  # The tail approach...
  #
  # touch /var/log/apache2/error.log
  # touch /var/log/apache2/subversion.log
  # touch /var/log/apache2/access.log
  #
  # tail -f /var/log/apache2/error.log &
  # tail -f /var/log/apache2/subversion.log &
  # tail -f /var/log/apache2/access.log &

  # The direct approach...
  #
  ln -sf /dev/stderr /var/log/apache2/error.log
  ln -sf /dev/stdout /var/log/apache2/access.log
  ln -sf /dev/stdout /var/log/apache2/subversion.log

  exec "$@" </dev/null #>/dev/null 2>&1
else # dev
  rm -f /var/log/apache2/error.log
  rm -f /var/log/apache2/access.log
  rm -f /var/log/apache2/subversion.log

  httpd -k start
fi

# fallthrough...
exec "$@"

