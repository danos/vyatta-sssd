set resources service-users ldap acme.com base-dn ou=People,dc=acme,dc=com
set resources service-users ldap acme.com search-filter uid=ldapuser1
set resources service-users ldap acme.com tls cacert /config/ssl/ldap-ca.pem
set resources service-users ldap acme.com tls reqcert allow
set resources service-users ldap acme.com url ldap://192.168.122.161/
set interfaces openvpn vtun1 auth ldap acme.com

set resources service-users ldap fab.acme.com base-dn ou=Machine,dc=acme,dc=com
set resources service-users ldap fab.acme.com search-filter uid=machineuser1
set resources service-users ldap fab.acme.com tls cacert /config/ssl/ldap-ca.pem
set resources service-users ldap fab.acme.com tls reqcert allow
set resources service-users ldap fab.acme.com url ldap://192.168.122.161/
set interfaces openvpn vtun1 auth ldap fab.acme.com
