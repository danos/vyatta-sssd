# Copyright (c) 2019-2020 AT&T intellectual property.
# All rights reserved.
#
# Copyright (c) 2014, 2017 Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

package Vyatta::SSSD::Local;

use warnings;
use strict;

use lib "/opt/vyatta/share/perl5";

use Vyatta::Config;

use Exporter q{import};
our @EXPORT = qw(
                   add_group
                   delete_group
                   delete_user
                   groupmod_append_group
                   groupmod_remove_group
                   list_groups
                   list_sssd_group_member_groups
                   local_groups
                   local_users
                   update_user
                   user_add_group
                   user_groups
                   user_remove_group
		);


my $SSSD_DOMAIN = 'local';
my $SSSD_LDB = '/var/lib/sss/db/sssd.ldb';
my $RESERVED_PREFIX = 'vyatta-';
my $GENERIC_SERVICE_USER_GROUP = $RESERVED_PREFIX.'service-users';
my $CONFIG_SPACE = 'resources service-users';

# Deletes group from local SSSD domain.
# Also the membership of all users to that group gets deleted.
sub delete_group {
    my $group = shift;
    my $rc = `sss_groupdel '$group' 2>&1 >/dev/null`;
    die "Could not remove group '$group':\n$rc" if ($?);
}

#  If group is known to local SSSD domain returns 1.
#  0 otherwise.
sub sssd_group_exists {
    my $group = shift;
    my $ret = 1;

    `sss_groupshow '$group' &> /dev/null`;
    $ret = 0 if ($?);

    return $ret;
}

# Creates group in local SSSD domain.
# If group is already known to local SSSD, creation gets skipped to prevent
# error messages.
sub add_group {
    my $group = shift;

    # Skip if group already exists
    return if sssd_group_exists($group);

    my $rc = `sss_groupadd '$group' 2>&1 >/dev/null`;
    die "Could not add group '$group':\n$rc" if ($?);
}

# The local SSSD domain allows to have user and group members
# in a group.
sub _list_sssd_groupshow_members {
    my $group = shift;
    my $membertype = shift;

    my @out = `sss_groupshow '$group'`;
    return () if ($?);

    my @memberstr = grep /Member $membertype:/, @out;
    $memberstr[0] =~ s/Member $membertype: //g;
    chomp $memberstr[0];
    return () unless $memberstr[0];

    my @members = split(",", $memberstr[0]);
    return @members;
}

# List all user members of supplied $group currently known to
# SSSD local doamin
sub list_sssd_group_members {
    my $group = shift;

    return _list_sssd_groupshow_members($group, 'users');
}

# List all group members of supplied $group currently known to
# SSSD local doamin.
# Including internal vyatta- groups.
sub list_sssd_group_member_groups {
    my $group = shift;

    return _list_sssd_groupshow_members($group, 'groups');
}

# Let a group join another group in local SSSD domain
# If group was already member, the action gets skipped.
sub groupmod_append_group {
    my $group = shift;
    my $group_member = shift;

    # Skip, if group_member is already member of that group
    # So we can still catch all other sss_groupmod warnings/errors.
    return if grep { $_ eq $group } list_sssd_group_member_groups($group_member);

    my $rc = `sss_groupmod --append-group '$group_member' '$group' 2>&1 >/dev/null`;
    die "Could not add group-member '$group_member' to group '$group':\n$rc" if ($?);
}

# Remove a group from another group in local SSSD domain.
# If group was not member, the action gets skipped.
sub groupmod_remove_group {
    my $group = shift;
    my $group_member = shift;

    # Skip, if group_member is already member of that group
    # So we can still catch all other sss_groupmod warnings/errors.
    return unless grep { $_ eq $group } list_sssd_group_member_groups($group_member);

    my $rc = `sss_groupmod --remove-group '$group_member' '$group' 2>&1 >/dev/null`;
    die "Could not remove group-member'$group_member' to group '$group':\n$rc" if ($?);
}


# List all configured/staged groups as configured in the CLI.
sub list_groups {

    my $config = new Vyatta::Config;

    $config->setLevel("$CONFIG_SPACE local group");
    return $config->returnValues();
}

# Delete user in local SSSD domain
sub delete_user {
    my $user = shift;

    my $rc = `sss_userdel '$user' 2>&1 >/dev/null`;
    #die "Could not remove user '$user':\n$rc" if ($?);
}

# List all groups of a user
#
# Including reserved vyatta- groups.
#
# The `groups` call requires SSS support in NSS.
# groups might not work correctly if nss-sss is not present.
#
# groups is also not up-to-date if a user just got created,
# a new session/shell is required to bring the groups call up to date.
sub user_groups {
    my $user = shift;

    my @ret;

    my $rc = `groups '$user\@$SSSD_DOMAIN'`;
    die "Could not retrieves group membership of '$user':\n$rc" if ($?);

    $rc =~ s/^.*: //;
    my @groups = split(" ", $rc);

    foreach my $group (@groups) {
       push @ret, $group;
    }

    return @ret;
}

# Add user to a SSSD local domain group, if the user is not yet
# a member of that group.
sub user_add_group {
    my $user = shift;
    my $group = shift;

    # Skip, if user is already member of that group
    # So we can still catch all other sss_usermod warnings/errors.
    return if grep { $_ eq $user } list_sssd_group_members($group);

    my $rc = `sss_usermod --append-group '$group' '$user' 2>&1 >/dev/null`;
    die "Could not add '$user' to group '$group':\n$rc" if ($?);
}

# Remove user from a SSSD local domain group, if the user is member
# of that local domain group.
sub user_remove_group {
    my $user = shift;
    my $group = shift;

    # Check if user is in that group at all
    return unless grep { $_ eq $user } list_sssd_group_members($group);

    my $rc = `sss_usermod --remove-group '$group' '$user' 2>&1 >/dev/null`;
    die "Could not remove '$user' from group '$group':\n$rc" if ($?);
}


# Lock user. User must exist, error otherwise.
sub user_lock {
    my $user = shift;

    my $rc = `sss_usermod --lock '$user' 2>&1 >/dev/null`;
    die "Could not lock user '$user':\n$rc" if ($?);
}

# Unlock user. User must exist, error otherwise.
sub user_unlock {
    my $user = shift;

    my $rc = `sss_usermod --unlock '$user' 2>&1 >/dev/null`;
    die "Could not unlock user '$user':\n$rc" if ($?);
}


# Generic service-user group. All local service-users are part of
# that group. To distinguish later between other user roles stored
# in the same local domain.
sub create_generic_service_user_group {

    # Only create the group if it does not exist yet
    `sss_groupshow $GENERIC_SERVICE_USER_GROUP 2>&1 >/dev/null`;
    return unless ($?);

    my $out = `sss_groupadd $GENERIC_SERVICE_USER_GROUP 2>&1 >/dev/null`;
    die "Could not create generic service user group '$GENERIC_SERVICE_USER_GROUP':\n$out" if ($?);
}

# Updates the setting of a user from the CLI.
# If the user does not exist yet, the user gets created.
#
# Password in the CLI needs to be already encrypted, error otherwise.
#
# This function also clean-up stale group-memberships from older
# CLI configurations.
#
# This function should be called on each service-user local user
# change to determine if the user needs to be locked or unlocked.
sub update_user {
    my $user = shift;
    my $cfg = new Vyatta::Config;

    $cfg->setLevel("$CONFIG_SPACE local user $user");
    my $password = $cfg->returnValue('auth encrypted-password');
    my $fname = $cfg->returnValue('full-name');
    my $gecos = "";
    $gecos = "--gecos '$fname'" if ( defined($fname) and $fname ne "" );

    unless ($password) {
        warn "Encrypted password not in configuration for $user";
        return;
    }
    # Before the first user get created, we generate the generic service-user group
    # So this group starts with an higher group id then any other user-group.
    create_generic_service_user_group();

    my $new_user = undef;
    `getent passwd '$user\@$SSSD_DOMAIN' &> /dev/null`;
    # There seems to be a bug in GECOS handing, if set empty. Then the user can no longer be removed
    if ($?) {
        my $rc = `sss_useradd $gecos --no-create-home '$user' 2>&1 >/dev/null`;
        die "Could not add user '$user':\n$rc" if ($?);

        user_add_group($user, $GENERIC_SERVICE_USER_GROUP);

	$new_user = 1;
    }

    open my $fd => "| ldbmodify -H $SSSD_LDB -i &> /dev/null"
       or die "Could not set password for $user: $!";

    print $fd "dn: name=$user@".$SSSD_DOMAIN.",cn=users,cn=$SSSD_DOMAIN,cn=sysdb\n";
    print $fd "changetype: modify\n";
    print $fd "replace: userPassword\n";
    print $fd "userPassword: $password\n";
    close $fd or die "Could not set password for $user: $!";


    # Group
    foreach my $group ($cfg->returnValues('group')) {
        user_add_group($user, $group);
    }

    if ($cfg->exists('lock')) {
        user_lock($user);
    } else {
        user_unlock($user);
    }

    return if defined($new_user);
    ## All further actions are dedicated for existing users

    foreach my $group ( user_groups($user) ) {
        # Group is still set in CLI, keep it.
        next if defined $cfg->exists("group $group");
        # Skip user-specific groups.
        next if $user eq $group;
        # Skip internal/system groups
        next if $group =~ /^$RESERVED_PREFIX/;

        user_remove_group($user, $group);
    }
}

# returns user list of current SSSD local domain content
sub local_users {
    my @users;

    my $query = `ldbsearch -H $SSSD_LDB -b cn=users,cn=$SSSD_DOMAIN,cn=sysdb '(objectClass=user)' name 2>&1`;
    die "Could not query list of all local service-users:\n$query" if ($?);

    while ($query =~ /name: ([^\n]+)\n?/g) {
        push @users, $1;
    }
    return @users;
}

# returns group list of current SSSD local domain content
sub local_groups {
    my @groups;

    my $query = `ldbsearch -H $SSSD_LDB -b cn=groups,cn=$SSSD_DOMAIN,cn=sysdb '(objectClass=group)' name 2>&1`;
    die "Could not query list of service-user groups:\n$query" if ($?);

    while ($query =~ /name: ([^\n]+)\n?/g) {
        next if $1 =~ /^$RESERVED_PREFIX/;
        push @groups, $1;
    }
    return @groups;
}

1;
