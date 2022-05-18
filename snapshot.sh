#!/bin/bash
# - snapshot.sh
#

set -e

USAGE="
Usage:

1. Create
    Command: 
        $ snapshot.sh create

    The following environment variables are needed to create a snapshot,
      - MYSQL_HOST: mysql user
      - MYSQL_USER: mysql user
      - MYSQL_PASSWORD: mysql password
      - MYSQL_DATA_DIR: mysql data directory(default: /var/lib/mysql)
      - SNAPSHOT_BASE_DIR: path to store backups (default: /data/snapshot)

2. Rollback
    Command: 
        $ snapshot.sh rollback <path/to/file>

    For example, rollback the snapshot at 2022051510(1652608800),
        $ snapshot.sh rollback 1652608800


3. Rotate
    Command: 
        $ snapshot.sh rotate <days>

    For example, cleanup the snapshots 10 days ago,
        $ snapshot.sh rotate 10
"

usage() {
    echo $USAGE
    exit 1
}


MYSQL_DATA_DIR=${MYSQL_DATA_DIR:-/var/lib/mysql}
SNAPSHOT_BASE_DIR=${SNAPSHOT_BASE_DIR:-/data/snapshot}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASSWORD}
MYSQL_HOST=${MYSQL_HOST}

export PATH=$(dirname "$0"):$PATH

create() {
    base_dir=$SNAPSHOT_BASE_DIR/$(date +%Y-%m)
    full_backup_dir=$base_dir/fullbackup

    backup_type=incremental
    if [ ! -d "$full_backup_dir" ];then
        backup_type=fullbackup
    fi
    
    if [ "$backup_type" = "fullbackup" ];then
        mkdir -p $full_backup_dir
        mariabackup --backup \
            --compress \
            --compress-threads=12 \
            --user $MYSQL_USER \
            --password $MYSQL_PASSWORD \
            --host $MYSQL_HOST \
            --datadir $MYSQL_DATA_DIR \
            --target-dir $full_backup_dir
    else
        inc_dir=$base_dir/$(date +%s)
        mkdir -p $inc_dir
        mariabackup --backup \
            --compress \
            --compress-threads=12 \
            --user $MYSQL_USER \
            --password $MYSQL_PASSWORD \
            --host $MYSQL_HOST \
            --datadir $MYSQL_DATA_DIR \
            --target-dir $inc_dir \
            --incremental-basedir $full_backup_dir
    fi

    if [ ! "$?" -eq 0 ];then
        echo "Failed!"
        exit 1
    fi

    echo "Success."
    exit 0
}

rollback() {
    snapshot=$1
    base_dir=$SNAPSHOT_BASE_DIR/$(date -d @$snapshot +%Y-%m)
    full_backup_dir=$base_dir/fullbackup

    mariabackup --decompress --target-dir $full_backup_dir
    if [ "$?" -eq 0 ];then
        mariabackup --decompress --target-dir $base_dir/$snapshot
    fi

    if [ "$?" -ne 0 ];then
        echo "decompress failed!"
        exit 1
    fi

    mariabackup --prepare --target-dir $full_backup_dir
    if [ "$?" -eq 0 ];then
        mariabackup --prepare \
            --incremental-dir $base_dir/$snapshot \
            --target-dir $full_backup_dir
    fi

    if [ "$?" -ne 0 ];then
        echo "prepare failed!"
        exit 1
    fi    
    rm -rf $MYSQL_DATA_DIR
    mariabackup --copy-back \
        --datadir $MYSQL_DATA_DIR \
        --target-dir $full_backup_dir

    mysqladmin \
        --user $MYSQL_USER \
        --host $MYSQL_HOST \
        -p $MYSQL_PASSWORD \
        shutdown
}


rotate() {
    ROTATION_WINDOW=${1:-30}
    for t in $(ls $SNAPSHOT_BASE_DIR);do
        if ! echo $t | grep -P '\d+-\d+';then
            continue
        fi

        month_last_day=$(date -d "$t-01 +1 month -1 day" +%s)
        gap=$(( $(date +%s) - $month_last_day ))

        if [ "$gap" -gt "$(($ROTATION_WINDOW * 86400))" ];then
            rm -rf $SNAPSHOT_BASE_DIR/$t
        else
            for i in $(ls $SNAPSHOT_BASE_DIR/$t);do
                if ! echo $i | egrep  '[0-9]+';then
                    continue
                fi

                gap=$(( $(date +%s) - $i ))
                if [ "$gap" -gt "$(($ROTATION_WINDOW * 86400))" ];then
                    rm -rf $SNAPSHOT_BASE_DIR/$t/$i
                fi
            done
        fi
    done
}

$@
