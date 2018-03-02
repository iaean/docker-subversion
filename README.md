# docker-subversion
Docker container for [Subversion][1] with [WebSVN][2].

[1]: http://subversion.apache.org/
[2]: https://websvnphp.github.io/

## Features
* Provides coexistent access via [`svn://`][3] and [`http[s]://`][4]
* Ultra small [Alpine Linux][5] based image
* LDAP and/or local password database based authentication via SASL
* [Path based authorization][6]
* Complete autoconfiguration via environment
* Repository grouping via SVN parent path
* Fancy SVN DAV [repository group browsing][7] inspired by [Apaxy][8]

[3]: http://svnbook.red-bean.com/de/1.7/svn.serverconfig.svnserve.html
[4]: http://svnbook.red-bean.com/de/1.7/svn.serverconfig.httpd.html
[5]: https://alpinelinux.org/
[6]: http://svnbook.red-bean.com/de/1.7/svn.serverconfig.pathbasedauthz.html
[7]: http://httpd.apache.org/docs/2.4/mod/mod_autoindex.html
[8]: https://oupala.github.io/apaxy/

## Installation
* Get it from docker hub
* or build the image as you normally would: `docker build --tag=subversion ./`
* Setting your environment
* Yee-haw...

## Configuration

### Persistent storage

### Repository groups

### Autoconfiguration via environment
| Variable | Scope | Default | Example |
| --- | --- | --- | --- |
| SUBVERSION_REPOS | recommended | sandbox/test | **legacy**/code **legacy**/conf **dev**/apps **prod**/apps |
| DESCRIPTION_**legacy** | recommended | | Legacy stuff |
| DESCRIPTION_**prod** | recommended | | Production app code & config |
| DESCRIPTION_**dev** | recommended | | Development app code & config |
| SVN_LOCAL_ADMIN_USER | recommended | | admin |
| SVN_LOCAL_ADMIN_PASS | recommended | | password |
| LDAP_BindDN | optional \| LDAP mandatory | | uid=root,cn=users,dc=example,dc=com |
| LDAP_BindPW | optional \| LDAP mandatory | | password |
| LDAP_Use_TLS |optional | no | yes \| no |
| LDAP_TLS_Ciphers | optional | | |
| LDAP_TLS_VerifyCert | optional | allow | never \| allow \| try \| demand |
| APACHE_LDAP_ALIAS | optional \| LDAP mandatory | | synology |
| APACHE_LDAP_URL | optional \| LDAP mandatory | | ldaps://synology/cn=users,dc=example,dc=com?uid?sub |
| SASL_LDAP_SERVER | optional \| LDAP mandatory | | ldaps://synology |
| SASL_LDAP_SEARCHBASE | optional \| LDAP mandatory | | cn=users,dc=example,dc=com |
| SASL_LDAP_FILTER | optional \| LDAP mandatory | | (uid=%U) |

## Running

### Running the docker image
Use docker to run the container as you normally would.

Production:

`docker run -p 80:80 -p 3690:3690 --env-file env --rm --name subversion subversion`

Devolopment:

`docker run -it -p 80:80 -p 3690:3690 --env-file env --rm --name subversion subversion /bin/sh`

`docker exec -it subversion /bin/sh`

`docker exec -u apache -it subversion /bin/sh`

### Setting local user passwords
We are using Apache htpasswd for `httpd` local auth and SASL for `svnserve` local auth. Unfortunately we had to maintain both auth sources until now.

`docker exec -u apache -it subversion sasldblistusers2 -f .svn.sasldb`

`docker exec -u apache -it subversion saslpasswd2 -f .svn.sasldb -u "Local or LDAP Account" foobar`

`docker exec -u apache -it subversion htpasswd -mb .htpasswd foobar password`

## TODO
* Apache publishes XML for repository indexing. This is transformed to HTML via [XSLT][9]. Make the XSLT looks smooth like the group listing HTML to avoid the visual break at SVN DAV browsing.
* **Bind** mount volumes under Docker for Windows should not be used actually, because they are [problematic][10] due to `chmod` and `chown`. Files are created as user `root` and this cannot be changed. Just, there is no workaround for this behaviour. Maybe a configurable solution could be to run `httpd` and `svnserve` as `root`, if this becomes an issue.
* It's annoying to maintain two local password databases actually. The solution is to enable SASL for Apache. Because there is no SASL auth feature in the official vanilla distribution, we could try to make [mod-authn-sasl][11] running.

[9]: https://svn.apache.org/repos/asf/subversion/trunk/tools/xslt/svnindex.xsl
[10]: https://docs.docker.com/docker-for-windows/troubleshoot/#permissions-errors-on-data-directories-for-shared-volumes
[11]: https://sourceforge.net/projects/mod-authn-sasl

## Towards SSL/TLS and Alpine
Alpine Linux is linking almost all packages against [LibreSSL][12]. LibreSSL should be compatible to [OpenSSL][13]. But it ***isn't***. I fought against a bug in LibreSSL a couple of days. There are servers with certificates from well-known CA's and OpenSSL works like a charm. But LibreSSL ***doesn't***. This is because of a bug in LibreSSL with TLSv1.2 and elliptic curve handshaking. <sup id="a1">[(1)](#f1)</sup><sup id="a1">[(2)](#f2)</sup>

In my opinion, this is a **major drawback** for Alpine Linux, because it can **break** SSL/TLS security for **any package**. In our case OpenLDAP via SASL and Apache. Beside [nginx][14] I don't know about an application that support feeding *Elliptic curve groups* to their TLS stack. The workaround for our case was a forced downgrade to AES128-SHA cipher. And feeding ciphers is supported by OpenLDAP. But feeding *Elliptic curve groups* isn't. It could have been worse.

If you run into this issue, try to use `LDAP_TLS_Ciphers` and hoping your server supports some working fallback.

[12]: http://www.libressl.org/
[13]: https://www.openssl.org/
[14]: https://nginx.org/

```bash
# Uhmpf... BROKEN!!
#
echo | openssl s_client -connect sec.srv.tld:636 -tls1_2 | egrep 'Cipher|Protocol'
140182729145292:error:140040E5:SSL routines:CONNECT_CR_SRVR_HELLO:ssl handshake failure:ssl_pkt.c:585:
New, (NONE), Cipher is (NONE)
    Protocol  : TLSv1.2
    Cipher    : 0000

# Works. But negotiates to AES128-SHA only.
#
echo | openssl s_client -connect sec.srv.tld:636 -tls1_2 -groups secp256k1:secp224r1 2>/dev/null | egrep 'Cipher|Protocol'
New, TLSv1/SSLv3, Cipher is AES128-SHA
    Protocol  : TLSv1.2
    Cipher    : AES128-SHA

# Works. But needs forced cipher.
#
echo | openssl s_client -connect sec.srv.tld:636 -tls1_2 -cipher AES128-SHA 2>/dev/null | egrep 'Cipher|Protocol'
New, TLSv1/SSLv3, Cipher is AES128-SHA
    Protocol  : TLSv1.2
    Cipher    : AES128-SHA

# TLSv1.1 works fine.
#
echo | openssl s_client -connect sec.srv.tld:636 -tls1_1 2>/dev/null | egrep 'Cipher|Protocol'
New, TLSv1/SSLv3, Cipher is ECDHE-RSA-AES128-SHA
    Protocol  : TLSv1.1
    Cipher    : ECDHE-RSA-AES128-SHA
```

> Written with [StackEdit](https://stackedit.iaean.net/).

[15]: http://svnbook.red-bean.com/de/1.7/svn.ref.svnserve.html
[16]: http://svnbook.red-bean.com/de/1.7/svn.ref.mod_dav_svn.conf.html
[17]: http://svnbook.red-bean.com/de/1.7/svn.ref.mod_authz_svn.conf.html

---
<span id="f1">1)</span> https://bugs.alpinelinux.org/issues/8199 [↩](#a1)   
<span id="f2">2)</span> https://github.com/libressl-portable/openbsd/issues/79 [↩](#a2)
