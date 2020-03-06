# -*- coding: utf-8 -*-
#
# Copyright (c) 2019-2020 AT&T intellectual property.
# All rights reserved.
#
# Copyright (c) 2014, 2017 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

import os
import syslog
import SSSDConfig

class SSSD(SSSDConfig.SSSDConfig):

	SCHEMA_API='/usr/share/doc/sssd/sssd.api.d'
	SCHEMA_FILE='/usr/share/doc/sssd/sssd.api.conf'
	SSSD_CONFIG = '/etc/sssd/sssd.conf'

	# Not yet requested sssd-ldap option are disabled for now
        # until requested.
	LDAP_OPTS = {
		'url': 'ldap_uri',
		'base-dn': 'ldap_search_base',
		'schema': 'ldap_schema', # rfc2307 vs. rfc2307bis
		'bind-dn': 'ldap_default_bind_dn',
		'password': 'ldap_default_authtok',

		## User attributes
		#'user search-base': 'ldap_user_search_base',
		#'user object-class': 'ldap_user_object_class',
		#'user name-attribute': 'ldap_user_name',
		#'user uid-attribute': 'ldap_user_uid_number',
		#'user gid-attribute': 'ldap_user_gid_number',
		#'user gecos-attribute': 'ldap_user_gecos',
		#'user home-directory-attribute': 'ldap_user_home_directory',
		#'user shell-attribute': 'ldap_user_shell',
		#'user uuid-attribute': 'ldap_user_uuid',
		#'user cn-attribute': 'ldap_user_fullname',
		#'user member-of-attribute': 'ldap_user_member_of',

		#'force-upper-case-realm': 'ldap_force_upper_case_realm',

		## Group
		'group base-dn': 'ldap_group_search_base',
		#'group object-class': 'ldap_group_object_class',
		#'group name-attribute': 'ldap_group_name',
		#'group gid-attribute': 'ldap_group_gid_number',
		'group member-attribute': 'ldap_group_member',
		#'group uuid': 'ldap_group_uuid',

		## TLS
		'tls reqcert': 'ldap_tls_reqcert',
		'tls cacert': 'ldap_tls_cacert',
		#'tls cacertdir': 'ldap_tls_cacertdir', # would required maintaince of hashed cert dir
		#'tls id-use-start-tls': 'ldap_id_use_start_tls', # force TLS also for ID lookup, not only auth

		## SASL not yet supported
		#'sasl mech': 'ldap_sasl_mech',
		#'sasl authid': 'ldap_sasl_authid',

		## Misc
		#'pwd-policy': 'ldap_pwd_policy', # password expiration policy on client side
		#'dns-service-name': 'ldap_dns_service_name', # DNS-SD not yet supported

		'follow-referrals': 'ldap_referrals',
		'search-filter': 'ldap_access_filter',

                ## KRB not yet supported
		#'krb5 keytab': 'ldap_krb5_keytab',
		#'krb5 init-creds': 'ldap_krb5_init_creds',
		#'krb5 realm': 'krb5_realm',

		#'user-principal': 'ldap_user_principal', # krb specific

		#'default-authtok-type': 'ldap_default_authtok_type', # only one value possible: password

		## Timeout settings

		# might change in future in SSSD, with more fine-grain settings:
		#'timeout search': 'ldap_search_timeout',

		#'timeout network': 'ldap_network_timeout', # default: 5 seconds
		#'timeout opt': 'ldap_opt_timeout',         # default: 5 seconds
        }

	TACPLUS_OPTS = {
		# internal only: 'tacplus_shell',
		# internal only: 'tacplus_service',
		# internal only: 'tacplus_proto',
		# internal only: 'tacplus_user_gid',
		# internal only: 'tacplus_homedir',
	}

	def __init__(self):

		if not os.path.exists(self.SCHEMA_API):
			self.SCHEMA_API = None

		if not os.path.exists(self.SCHEMA_FILE):
			self.SCHEMA_FILE = None

		SSSDConfig.SSSDConfig.__init__(self, schemaplugindir=self.SCHEMA_API, schemafile=self.SCHEMA_FILE)

		if os.path.exists(self.SSSD_CONFIG):
			self.import_config(self.SSSD_CONFIG)
		else:
			self.new_config()

		# Always perform setup of the NSS service
		self._setup_nss()

	def try_set_domain_option(self, domain, opt, value):
		try:
			domain.set_option(opt, value)
		except SSSDConfig.NoOptionError as e:
			syslog.syslog(syslog.LOG_DEBUG, "Error setting option '{}' " \
				"on domain '{}': {}".format(opt, domain.get_name(), e))

	def setup_local(self):
		try:
			local_domain = self.get_domain('local')
		except SSSDConfig.NoDomainError:
			local_domain = self.new_domain('local')

		local_domain.add_provider('local', 'id')
		local_domain.add_provider('local', 'auth')
		# local domain does not provide an access provider
		#local_domain.add_provider('local', 'access')

		local_domain.set_option('enumerate', 'true')
		local_domain.set_option('min_id', 500)
		# No upper limit, required since there is no ID rotation:
		# http://www.redhat.com/archives/freeipa-devel/2009-March/msg00076.html
		# max_id is then UINT32_MAX
		local_domain.set_option('max_id', 0)
		local_domain.set_option('default_shell', '/bin/false')

		local_domain.set_active(True)
		self.save_domain(local_domain)

	def setup_ldap(self, name, options):
		try:
			ldap_domain = self.get_domain(name)
		except SSSDConfig.NoDomainError:
			ldap_domain = self.new_domain(name)

		ldap_domain.add_provider('ldap', 'id')
		ldap_domain.add_provider('ldap', 'auth')
		ldap_domain.add_provider('ldap', 'access')
		ldap_domain.set_active(True)

		# Following options are by default in SSSD true, but in the CLI
		# those are CLI:
		#
		#  * ldap_referrals
		#
                # Since we are using typeless-boolean, we disable those first. And
		# enable them if those are set in the CLI.

		for opt in ['ldap_referrals']:
			ldap_domain.set_option(opt, 'false')

		option_schema = ldap_domain.list_options()
		for opt in options:
			if option_schema[opt][0] == bool:
				ldap_domain.set_option(opt, 'true')
			else:
				ldap_domain.set_option(opt, options[opt])

		self.save_domain(ldap_domain)

	def setup_tacplus(self, name, options):
		try:
			tacplus_domain = self.get_domain(name)
		except SSSDConfig.NoDomainError:
			tacplus_domain = self.new_domain(name)

		tacplus_domain.add_provider('tacplus', 'id')
		tacplus_domain.add_provider('tacplus', 'auth')
		#tacplus_domain.add_provider('tacplus', 'access')
		tacplus_domain.set_active(True)

		option_schema = tacplus_domain.list_options()
		for opt in options:
			if option_schema[opt][0] == bool:
				tacplus_domain.set_option(opt, 'true')
			else:
				tacplus_domain.set_option(opt, options[opt])

		tacplus_domain.set_option('tacplus_shell', '/bin/vbash')
		tacplus_domain.set_option('tacplus_service', 'vyatta-exec')
		tacplus_domain.set_option('tacplus_secrets', 'true')
		tacplus_domain.set_option('tacplus_proto', 'login')
		tacplus_domain.set_option('tacplus_user_gid', '100')
		tacplus_domain.set_option('tacplus_homedir', '/var/tmp/aaa-home/%u')
		tacplus_domain.set_option('entry_cache_user_timeout', '3600')
		tacplus_domain.set_option('min_id', '2000')
		tacplus_domain.set_option('offline_timeout', '60')
		tacplus_domain.set_option('offline_timeout_max', '0')
		tacplus_domain.set_option('propagate_provider_error', 'true')


		self.save_domain(tacplus_domain)


	def _setup_nss(self):
		try:
			nss_serv = self.get_service("nss")
		except SSSDConfig.NoServiceError:
			nss_serv = self.new_service("nss")

		# NSS requests for filtered users are ignored.
		# "*" is ignored since a request for this user is generated
		# when path completion is requested in Bash, due to a bug in
		# the completion script. See Debian bug #825317.
		# root is ignored by default so is also set here.
		nss_serv.set_option("filter_users", "root,*")

		# By default local users are kept in the negative cache for
		# 4 hours. When there is a negative cache hit the data provider
		# (eg. TACACS+) is not queried, which means we don't determine
		# whether the provider is offline, which results in local user
		# fallback not working reliably.
		# Setting it to 0 means that all negative cache entries timeout
		# according to entry_negative_timeout, which defaults to 15 seconds.
		nss_serv.set_option("local_negative_timeout", 0)

		self.save_service(nss_serv)


	def commit(self):
		# Created files needs to be owned by root and root group.
                # If not SSSD refuses to start. Even the file SSSD creates during
                # startup require to have the gid() set.
		prevGid = os.getgid()
		os.setgid(0)

		self.write(self.SSSD_CONFIG)

		# Generate /etc/default/sssd
		etc_default_sssd_content = """##
## This file is auto-generated by vyatta-sssd.
## Do not edit, all changes will be lost!
##
"""

		if len(self.list_domains()) == 0:
			# SSSD fails to start on boot-up with no domains
			# configured. Due to absence of chkconfig and friends
			# SSSD init-startup get avoided by the sourced default sssd
			# config file, which does not exist by default.
			etc_default_sssd_content += """
# No SSS domains configured - disabling SSSD -vyatta-sssd
exit 0
"""

		with open('/etc/default/sssd', 'w') as f:
			f.write(etc_default_sssd_content)

		# Once the default/sssd configuration got written we invoke
		# the SSSD init script.
		if len(self.list_domains()) > 0:
			os.system('service sssd restart &> /dev/null');
		else:
			os.system('service sssd stop &> /dev/null');

		os.setgid(prevGid)

