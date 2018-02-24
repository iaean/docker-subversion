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

APACHE_LDAP_ALIAS=synology
APACHE_LDAP_URL=ldaps://synology/cn=users,dc=example,dc=com?uid?sub

SASL_LDAP_SERVER=ldaps://synology
SASL_LDAP_SEARCHBASE=cn=users,dc=example,dc=com
SASL_LDAP_FILTER=(uid=%U)

### Towards SSL/TLS and Alpine

### TODO
