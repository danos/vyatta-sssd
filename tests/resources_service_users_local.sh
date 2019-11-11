function create_user() {
	set resources service-users local user $1 auth plaintext-password "foo"
	set resources service-users local user $1 full-name "Dummy $1"
}

function setup_full_testbed() {
	set resources service-users local group sales-dep
	set resources service-users local group hr-dep

	create_user foobar
	set resources service-users local user foobar group sales-dep
	set resources service-users local user foobar group hr-dep

	create_user jdoe
	set resources service-users local user jdoe group hr-dep
}

function lookup_user() {
	ldbsearch -H /var/lib/sss/db/sssd.ldb -b cn=users,cn=LOCAL,cn=sysdb "(name=$1)" 2> /dev/null | grep -q "0 entries" && return 1
        return 0
}

function lookup_group() {
	ldbsearch -H /var/lib/sss/db/sssd.ldb -b cn=groups,cn=LOCAL,cn=sysdb "(name=$1)" 2> /dev/null | grep -q "0 entries" && return 1
        return 0
}


function reset_sssd_nextid() {

	( cat << EOF
dn: cn=LOCAL,cn=sysdb
changetype: modify
replace: nextID
nextID: 500
EOF
	) | ldbmodify -H /var/lib/sss/db/sssd.ldb -i &> /dev/null
}


(
sss_userdel foobar
sss_userdel jdoe
sss_groupdel sales-dep
sss_groupdel hr-dep
sss_groupdel marketing-dep
sss_groupdel it-dep

for testuser in $( ldbsearch -H /var/lib/sss/db/sssd.ldb -b cn=users,cn=LOCAL,cn=sysdb name | egrep "^name:" | sed 's/name: //g' ); do
	sss_userdel $testuser;
done

) &> /dev/null


echo "Cleanup"
delete resources service-users local &> /dev/null
commit
reset_sssd_nextid



echo "Setup testbed"
setup_full_testbed
commit

echo "Testcase: verify correct SSSD user creation"
id foobar@LOCAL &> /dev/null || echo FAILED_SSSD_CREATE_USER1
lookup_user foobar || echo FAILED_SSSD_SYSDB_CREATE_USER1
id jdoe@LOCAL &> /dev/null || echo FAILED_SSSD_CREATE_USER2
sss_groupshow vyatta-service-users 2> /dev/null | grep -q foobar || echo FAILED_CRATE_USER1_SERVICE_GROUP_ASSIGNMENT
sss_groupshow vyatta-service-users 2> /dev/null | grep -q jdoe || echo FAILED_CRATE_USER2_SERVICE_GROUP_ASSIGNMENT

echo "Testcase: verify correct SSSD group assignment"
groups foobar@LOCAL | grep -q hr-dep || echo FAILED_SSSD_USER_GROUP
groups foobar@LOCAL | grep -q sales-dep || echo FAILED_SSSD_USER_GROUP2

groups jdoe@LOCAL | grep -q hr-dep || echo FAILED_SSSD_USER2_GROUP
groups jdoe@LOCAL | grep -q sales-dep && echo FAILED_SSSD_USER2_GROUP2


show resources service-users local user foobar group | grep -q sales-dep || echo FAILED_USER_GROUP
show resources service-users local user foobar group | grep -q hr-dep || echo FAILED_USER_GROUP2
show resources service-users local user jdoe group | grep -q sales-dep && echo FAILED_WRONG_USER_GROUP
show resources service-users local user foobar full-name | grep -q "Dummy foobar" || echo FAILED_USER_FULL_NAME
show resources service-users local user foobar auth plaintext-password | grep -q "" || echo FAILED_ONLY_ENCRYPTED_PASSWORD
show resources service-users local user foobar auth encrypted-password | grep -q " \$6" || echo FAILED_ENCRYPTED_PASSWORD

echo "Testcase: service-user change password"
set resources service-users local user foobar auth plaintext-password "foobar"
commit
show resources service-users local user foobar auth plaintext-password | grep -q "" || echo FAILED_ONLY_ENCRYPTED_CHANGED_PASSWORD
show resources service-users local user foobar auth encrypted-password | grep -q " \$6" || echo FAILED_ENCRYPTED_CHANGED_PASSWORD

echo "Testcase: service-user change full-name"
set resources service-users local user foobar full-name "Foo Bar"
commit
show resources service-users local user foobar full-name | grep -q "Foo Bar" || echo FAILED_CHANGING_FULLNAME



echo "Testcase: locking of local service-user"
set resources service-users local user foobar lock
commit
show resources service-users local user foobar | egrep -q lock || echo FAILED_USER_LOCK_USER1
ldbsearch -H /var/lib/sss/db/sssd.ldb -b cn=users,cn=LOCAL,cn=sysdb "(name=foobar)" disabled 2> /dev/null | grep -q "disabled: true"  || echo FAILED_USER_LOCK_SYSDB_USER1

echo "Testcase: unlocking of local service-user"
delete resource service-users local user foobar lock
commit
show resources service-users local user foobar | egrep -q lock && echo FAILED_USER_UNLOCK_USER1
ldbsearch -H /var/lib/sss/db/sssd.ldb -b cn=users,cn=LOCAL,cn=sysdb "(name=foobar)" disabled 2> /dev/null | grep -q "disabled: true"  && echo FAILED_USER_UNLOCK_SYSDB_USER1

echo "Testcase: check for stale group ownership in CLI, when group is deleted"
delete resources service-users local group sales-dep
commit

show resources service-users local user foobar group | grep -q sals-dep && echo FAILED_USER_STALE_GROUP
show resources service-users local user foobar group | grep -q hr-dep || echo FAILED_USER_GROUP_ON_CLEANUP__VYATTA_CFG_KNOWN_ISSUE


### This case is not valid, due to FAILED_USER_GROUP_ON_CLEANUP__VYATTA_CFG_KNOWN_ISSUE
### hr-dep group alrady got deleted unintetionally in previous testcase
#echo "Testcase: delete group membership of a user. Expected: group still exists, user is no longer group membership"
#delete resources service-users local user foobar group hr-dep
#commit
#
#id foobar@LOCAL &> /dev/null || echo FAILED_GROUP_USER1_LOST
#groups foobar@LOCAL | grep -q hr-dep && echo FAILED_TO_DROP_HR_GROUP_SSSD
#show resources service-users local user foobar | grep -q hr-dep && echo FAILED_TO_DROP_HR_GROUP_CLI

echo "Testcase: delete entrie group section with multiple group entries"
set resources service-users local group marketing-dep
set resources service-users local group it-dep
commit
delete resources service-users local group
commit
show resources service-users local | grep -q group && echo FAILED_DELETE_ENTRIE_GROUP

echo "Testcase: delete single service-user"
delete resources service-users local user foobar
commit
id foobar@LOCAL &> /dev/null && echo FAILED_SSSD_DELETE_USER1
lookup_user foobar && echo FAILED_SSSD_SYSDB_DELETE_USER1
groups foobar@LOCAL &> /dev/null && echo FAILED_SSSD_DELETE_USER_GROUP
show resources service-users local user | grep -q foobar && echo FAILLED_DELETE_USER1

echo "Testcase: delete entire service-user user section with multiple user entries"
create_user foobar
commit
delete resources service-users local user
commit
id foobar@LOCAL &> /dev/null && echo FAILED_SSSD_DELETE_ENTIRE_USER_SECTION_USER1
lookup_user foobar && echo FAILED_SSSD_SYSDB_DELETE_ENTIRE_USER_SECTION_USER1
id jdoe@LOCAL &> /dev/null && echo FAILED_SSSD_DELETE_ENTIRE_USER_SECTION_USER2
groups foobar@LOCAL &> /dev/null && echo FAILED_SSSD_DELETE_USER_GROUP_ENTIRE_USER_SECTION_USER1
groups jdoe@LOCAL &> /dev/null && echo FAILED_SSSD_DELETE_USER_GROUP_ENTIRE_USER_SECTION_USER2
show resources service-users local | grep -q user && echo FAILLED_DELETE_USER_SECTION

echo "Testcase: delete multiple users and groups by deleting entire local service-users section"
setup_full_testbed
commit
id foobar@LOCAL &> /dev/null || echo FAILED_ROUND2_SSSD_CREATE_USER1
lookup_user foobar || echo FAILED_ROUND2_SSSD_SYSDB_CREATE_USER1
id jdoe@LOCAL &> /dev/null || echo FAILED_ROUND2_SSSD_CREATE_USER2
delete resources service-users local
commit
show resources service-users | grep -q local && echo FAILLED_DELETE_LOCAL_SECTION
lookup_user foobar && echo FAILED_SSSD_DELETE_SYSDB_ENTIRE_LOCAL_SECTION_USER1
id foobar@LOCAL &> /dev/null && echo FAILED_SSSD_DELETE_ENTIRE_LOCAL_SECTION_USER1
groups foobar@LOCAL &> /dev/null && echo FAILED_SSSD_DELETE_USER_GROUP_ENTIRE_LOCAL_SECTION_USER1
lookup_group foobar && echo FAILED_SSSD_DELETE_SYSDB_ENTIRE_LOCAL_SECTION_USER1_GROUP

id jdoe@LOCAL &> /dev/null && echo FAILED_SSSD_DELETE_ENTIRE_LOCAL_SECTION_USER2
groups jdoe@LOCAL &> /dev/null && echo FAILED_SSSD_DELETE_USER_GROUP_ENTIRE_LOCAL_SECTION_USER2

lookup_group sales-dep && echo FAILED_SSSD_DELETE_SYSDB_ENTIRE_LOCAL_SECTION_GROUP1
lookup_group hr-dep && echo FAILED_SSSD_DELETE_SYSDB_ENTIRE_LOCAL_SECTION_GROUP2

echo "Testcase: delete multiple users and groups by deleting entire service-users section"
setup_full_testbed
commit
id foobar@LOCAL &> /dev/null || echo FAILED_ROUND3_SSSD_CREATE_USER1
id jdoe@LOCAL &> /dev/null || echo FAILED_ROUND3_SSSD_CREATE_USER2
delete resources service-users
commit
show resources | grep -q service-users && echo FAILLED_DELETE_SERVICE_USERS_SECTION
id foobar@LOCAL &> /dev/null && echo FAILED_SSSD_DELETE_ENTIRE_SERVICE_USERS_SECTION_USER1
lookup_user foobar && echo FAILED_SSSD_DELETE_SYSDB_ENTIRE_LOCAL_SECTION_USER1

groups foobar@LOCAL &> /dev/null && echo FAILED_SSSD_DELETE_USER_GROUP_ENTIRE_SERVICE_USERS_SECTION_USER1
lookup_group foobar && echo FAILED_SSSD_DELETE_SYSDB_ENTIRE_LOCAL_SECTION_USER1_GROUP

id jdoe@LOCAL &> /dev/null && echo FAILED_SSSD_DELETE_ENTIRE_SERVICE_USERS_SECTION_USER2
groups jdoe@LOCAL &> /dev/null && echo FAILED_SSSD_DELETE_USER_GROUP_ENTIRE_SERVICE_USERS_SECTION_USER2

lookup_group sales-dep && echo FAILED_SSSD_DELETE_SYSDB_ENTIRE_LOCAL_SECTION_GROUP1
lookup_group hr-dep && echo FAILED_SSSD_DELETE_SYSDB_ENTIRE_LOCAL_SECTION_GROUP2


PAM_SERVICE_USERS_CONF="/etc/pam.d/vyatta-service-users.conf"
echo "Testcase: verify generated service-user PAM configuration file"
setup_full_testbed
commit
test -f $PAM_SERVICE_USERS_CONF || echo FAILED_PAM_NOT_GENERATED_MISSING
grep -q "^auth required pam_deny.so" $PAM_SERVICE_USERS_CONF || echo FAILED_PAM_CONF_MISSING_AUTH_DENY
grep -q "^account required pam_deny.so" $PAM_SERVICE_USERS_CONF || echo FAILED_PAM_CONF_MISSING_ACCOUNT_DENY
egrep -q "^auth sufficient pam_sss.so" $PAM_SERVICE_USERS_CONF || echo FAILED_PAM_CONF_MISSING_AUTH_PAM_SSS
egrep -q "^account sufficient pam_sss.so" $PAM_SERVICE_USERS_CONF || echo FAILED_PAM_CONF_MISSING_ACCOUNT_PAM_SSS
egrep -q "^auth sufficient pam_sss.so domains=local" $PAM_SERVICE_USERS_CONF || echo FAILED_PAM_CONF_INVALID_AUTH_PAM_SSS_CONFIG
egrep -q "^account sufficient pam_sss.so domains=local" $PAM_SERVICE_USERS_CONF || echo FAILED_PAM_CONF_INVALID_ACCOUNT_PAM_SSS_CONFIG

echo "Testcase: verify locked service-user PAM configuration file with SSSD disabled"
delete resource service-users
commit
test -f $PAM_SERVICE_USERS_CONF || echo FAILED_PAM_NOT_GENERATED_MISSING
grep -q "^auth required pam_deny.so" $PAM_SERVICE_USERS_CONF || echo FAILED_PAM_CONF_MISSING_AUTH_DENY
grep -q "^account required pam_deny.so" $PAM_SERVICE_USERS_CONF || echo FAILED_PAM_CONF_MISSING_ACCOUNT_DENY
egrep -q "^auth (required|sufficient) pam_sss.so" $PAM_SERVICE_USERS_CONF && echo FAILED_PAM_CONF_NOT_EXPECTING_AUTH_PAM_SSS
egrep -q "^account (required|sufficient) pam_sss.so" $PAM_SERVICE_USERS_CONF && echo FAILED_PAM_CONF_NOT_EXPECTING_ACCOUNT_PAM_SSS






function bench_batch_user_creation() {

	NUMBER_OF_USERS=$1;
	echo "Testcase: creating $NUMBER_OF_USERS service-users in one commit"
	reset_sssd_nextid
	START_SET=$( date +%s )
	for n in $(seq 1 $NUMBER_OF_USERS); do
	     create_user testuser$n
	done
	START_COMMIT=$( date +%s )
	commit
	END_COMMIT=$( date +%s )
	echo "SET time: $(( $START_COMMIT - $START_SET ))s"
	echo "COMMIT time: $(( $END_COMMIT - $START_COMMIT ))s"
	delete resources service-users
	reset_sssd_nextid
	commit
}

bench_batch_user_creation 100
#bench_batch_user_creation 200
#bench_batch_user_creation 300
#bench_batch_user_creation 400
#bench_batch_user_creation 450
bench_batch_user_creation 500

