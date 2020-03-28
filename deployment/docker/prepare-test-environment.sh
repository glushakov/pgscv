#!/bin/bash

MAIN_DATADIR=/var/lib/postgresql/data/main
STDB_DATADIR=/var/lib/postgresql/data/standby

# init postgres
su - postgres -c "/usr/lib/postgresql/12/bin/initdb -k -E UTF8 --locale=en_US.UTF-8 -D ${MAIN_DATADIR}"

# add extra config parameters
echo "logging_collector = on" >> ${MAIN_DATADIR}/postgresql.auto.conf
echo "log_directory = '/var/log/postgresql'" >> ${MAIN_DATADIR}/postgresql.auto.conf
echo "track_io_timing = on" >> ${MAIN_DATADIR}/postgresql.auto.conf
echo "track_functions = all" >> ${MAIN_DATADIR}/postgresql.auto.conf
echo "shared_preload_libraries = 'pg_stat_statements'" >> ${MAIN_DATADIR}/postgresql.auto.conf
echo "host all  weaponry_app 127.0.0.1/32 trust" >> ${MAIN_DATADIR}/pg_hba.conf

# run main postgres
su - postgres -c "/usr/lib/postgresql/12/bin/pg_ctl -w -t 30 -l /var/run/postgresql/startup-main.log -D ${MAIN_DATADIR} start"
su - postgres -c "psql -c \"SELECT pg_create_physical_replication_slot('standby_test_slot')\""

# run standby postgres
su - postgres -c "pg_basebackup -P -R -X stream -c fast -h 127.0.0.1 -p 5432 -U postgres -D ${STDB_DATADIR}"
echo "port = 5433" >> ${STDB_DATADIR}/postgresql.auto.conf
echo "primary_slot_name = 'standby_test_slot'" >> ${STDB_DATADIR}/postgresql.auto.conf
echo "log_filename = 'postgresql-standby.log'" >> ${STDB_DATADIR}/postgresql.auto.conf
su - postgres -c "/usr/lib/postgresql/12/bin/pg_ctl -w -t 30 -l /var/run/postgresql/startup-standby.log -D ${STDB_DATADIR} start"

# add fixtures, tiny workload
su - postgres -c 'psql -f /usr/local/testing/fixtures.sql'
su - postgres -c "pgbench -i -s 5 pgbench"
su - postgres -c "pgbench -T 5 pgbench"

# configure pgbouncer
sed -i -e 's/^;* = host=testserver$/* = host=127.0.0.1/g' /etc/pgbouncer/pgbouncer.ini
sed -i -e 's/^;admin_users = .*$/admin_users = weaponry_app/g' /etc/pgbouncer/pgbouncer.ini
sed -i -e 's/^;pool_mode = session$/pool_mode = transaction/g' /etc/pgbouncer/pgbouncer.ini
sed -i -e 's/^;ignore_startup_parameters = .*$/ignore_startup_parameters = extra_float_digits/g' /etc/pgbouncer/pgbouncer.ini
echo '"weaponry_app" ""' > /etc/pgbouncer/userlist.txt

# run pgbouncer
su - postgres -c "/usr/sbin/pgbouncer -d /etc/pgbouncer/pgbouncer.ini"

# check services availability
pg_isready -t 10 -h 127.0.0.1 -p 5432 -U weaponry_app -d postgres
pg_isready -t 10 -h 127.0.0.1 -p 6432 -U weaponry_app -d pgbouncer
