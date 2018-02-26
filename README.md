# docker-subversion
Docker container for Subversion with WebSVN

## Features
...
Runs apache and svnserve to provide access via `svn://` and `http://`.

### Building the docker image
Use docker to build the image as you normaly would:
`docker build --tag=subversion ./`

### Running the docker image
Use docker to run the container as you normaly would:
`docker run -p 80:80 -p 3690:3690 --env-file env --rm --name subversion subversion`
`docker run -it -p 80:80 -p 3690:3690 --env-file env --rm --name subversion subversion /bin/sh`

`docker exec -it subversion /bin/sh`
`docker exec -u apache -it subversion /bin/sh`

### Setting local user paswords
`docker exec -u apache -it subversion sasldblistusers2 -f .svn.sasldb`
`docker exec -u apache -it subversion saslpasswd2 -f .svn.sasldb -u "Local or LDAP Account" foobar`
`docker exec -u apache -it subversion htpasswd -mb .htpasswd foobar password`

### Autoconfiguration via Environment
SUBVERSION_REPOS=legacy/code legacy/conf dev/apps prod/apps

DESCRIPTION_legacy=Legacy stuff
DESCRIPTION_prod=Production app code & config
DESCRIPTION_dev=Development app code & config

SVN_LOCAL_ADMIN_USER=admin
SVN_LOCAL_ADMIN_PASS=password

LDAP_BindDN=uid=root,cn=users,dc=example,dc=com
LDAP_BindPW=PASSWORD
LDAP_Use_TLS=no
LDAP_TLS_Ciphers=
LDAP_TLS_VerifyCert=

APACHE_LDAP_ALIAS=synology
APACHE_LDAP_URL=ldaps://synology/cn=users,dc=example,dc=com?uid?sub

SASL_LDAP_SERVER=ldaps://synology
SASL_LDAP_SEARCHBASE=cn=users,dc=example,dc=com
SASL_LDAP_FILTER=(uid=%U)

### Towards SSL/TLS and Alpine


```
# Uhmpf... BROKEN!!
echo | openssl s_client -connect sec.srv.tld:636 -tls1_2 | \
  egrep 'Cipher|Protocol'
140182729145292:error:140040E5:SSL routines:CONNECT_CR_SRVR_HELLO:ssl handshake failure:ssl_pkt.c:585:
New, (NONE), Cipher is (NONE)
    Protocol  : TLSv1.2
    Cipher    : 0000

# Works. But negotiates to AES128-SHA only.
echo | openssl s_client -connect sec.srv.tld:636 -tls1_2 \
  -groups secp256k1:secp224r1 2>/dev/null | egrep 'Cipher|Protocol'
New, TLSv1/SSLv3, Cipher is AES128-SHA
    Protocol  : TLSv1.2
    Cipher    : AES128-SHA

# Works. But needs forced cipher.
echo | openssl s_client -connect sec.srv.tld:636 -tls1_2 \
  -cipher AES128-SHA 2>/dev/null | egrep 'Cipher|Protocol'
New, TLSv1/SSLv3, Cipher is AES128-SHA
    Protocol  : TLSv1.2
    Cipher    : AES128-SHA

# TLSv1.1 works fine.
echo | openssl s_client -connect sec.srv.tld:636 -tls1_1 \
  2>/dev/null | egrep 'Cipher|Protocol'
New, TLSv1/SSLv3, Cipher is ECDHE-RSA-AES128-SHA
    Protocol  : TLSv1.1
    Cipher    : ECDHE-RSA-AES128-SHA
```

### TODO

fancy, windows bind, apache sasl




[]: https://bugs.alpinelinux.org/issues/8199 "LibreSSL Bug"
[]: https://github.com/libressl-portable/openbsd/issues/79 "LibreSSL Bug"
