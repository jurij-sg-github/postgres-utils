#!/bin/bash
#
# $CentOS$
#
# Maintenance shell script to vacuum and backup database
#

# daily_pgsql_backup_enable="YES" # do backup of all databases
# daily_pgsql_backup_enable="foo bar db1 db2" # only do backup of a limited selection of databases

daily_pgsql_backup_enable="YES" # do backup of all databases

daily_pgsql_mount_backup_share_enable="YES"
daily_pgsql_mount_nfs_server="10.10.10.10"
daily_pgsql_mount_nfs_share="/volume/something"
daily_pgsql_mount_nfs_mount_point="/mnt"

daily_pgsql_backupdir="/mnt/volume/something"


# defaults - there is usually no need to change anything below
: ${daily_pgsql_mount_backup_dir_enable:="NO"} do not mount backup directory
: ${daily_pgsql_vacuum_enable:="NO"} # do VACUUM on all databases
: ${daily_pgsql_savedays:="30"}
: ${daily_pgsql_user:="enterprisedb"}
: ${daily_pgsql_port:=5444}
: ${daily_pgsql_vacuum_args:="-U ${daily_pgsql_user} -p ${daily_pgsql_port} -qaz"}
: ${daily_pgsql_pgdump_args:="-U ${daily_pgsql_user} -p ${daily_pgsql_port} -bF c"}
: ${daily_pgsql_pgdumpall_globals_args:="-U ${daily_pgsql_user} -p ${daily_pgsql_port}"}

# allow '~´ in dir name
eval backupdir=${daily_pgsql_backupdir}

rc=0

mount_backup_share() {
	mount -v -t nfs ${daily_pgsql_mount_nfs_server}:${daily_pgsql_mount_nfs_share} ${daily_pgsql_mount_nfs_mount_point}
}

unmount_backup_share() {
	umount ${daily_pgsql_mount_nfs_mount_point}
}


pgsql_backup() {
	# daily_pgsql_backupdir must be writeable by user daily_pgsql_user
	if [ ! -d ${backupdir} ] ; then 
	    echo Creating ${backupdir}
	    mkdir -m 700 ${backupdir}; chown ${daily_pgsql_user} ${backupdir}
	fi

	echo
	echo "EDB backups"

	# Protect the data
	umask 077
	rc=$?
	now=`date "+%Y-%m-%dT%H:%M:%S"`
	file=${daily_pgsql_backupdir}/pgglobals_${now}
	su -l ${daily_pgsql_user} -c \
		"umask 077; pg_dumpall -g ${daily_pgsql_pgdumpall_globals_args} | gzip -9 > ${file}.gz"

	db=$1
	while shift; do
	    echo -n " $db"
	    file=${backupdir}/pgdump_${db}_${now}
	    su -l ${daily_pgsql_user} -c "umask 077; pg_dump ${daily_pgsql_pgdump_args} -f ${file} ${db}"
	    [ $? -gt 0 ] && rc=3
		db=$1
	done

	if [ $rc -gt 0 ]; then
	    echo
	    echo "Errors were reported during backup."
	fi

	# cleaning up old data
	find ${backupdir} \( -name 'pgdump_*' -o -name 'pgglobals_*' -o -name '*.dat.gz' -o -name 'toc.dat' \) \
	    -a -mtime +${daily_pgsql_savedays} -delete
	echo
}

case "$daily_pgsql_mount_backup_share_enable" in
    [Yy][Ee][Ss])

	echo
	echo "Mounting backup directory"
	mount_backup_share
	if [ $? -gt 0 ]
	then
	    echo
	    echo "Errors were reported during mount."
	    rc=3
	fi
	;;
esac

case "$daily_pgsql_backup_enable" in
    [Yy][Ee][Ss])
	dbnames=`su -l ${daily_pgsql_user} -c "umask 077; psql -U ${daily_pgsql_user} -p ${daily_pgsql_port} -q -t -A -d template1 -c SELECT\ datname\ FROM\ pg_database\ WHERE\ datname!=\'template0\'"`
	pgsql_backup $dbnames
	;;

	[Nn][Oo])
	;;

	"")
	;;

	*)
	pgsql_backup $daily_pgsql_backup_enable
	;;
esac

case "$daily_pgsql_mount_backup_share_enable" in
    [Yy][Ee][Ss])

	echo
	echo "Unmounting backup directory"
	unmount_backup_share
	if [ $? -gt 0 ]
	then
	    echo
	    echo "Errors were reported during unmount."
	    rc=3
	fi
	;;
esac


case "$daily_pgsql_vacuum_enable" in
    [Yy][Ee][Ss])

	echo
	echo "EDB vacuum"
	su -l ${daily_pgsql_user} -c "vacuumdb ${daily_pgsql_vacuum_args}"
	if [ $? -gt 0 ]
	then
	    echo
	    echo "Errors were reported during vacuum."
	    rc=3
	fi
	;;
esac

exit $rc
