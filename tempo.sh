#!/bin/bash

function purge_db {

echo "creating backup of IM db"

NOW=$(date +"%Y-%m-%d")

pg_dump -Fc im > $NOW.im.dump

echo "first step, deleting vlans, vlans_avertised, subnets content"

psql im << EOF
            DELETE FROM subnets;
            DELETE FROM vlans_advertised;
            DELETE FROM vlans;
            ALTER SEQUENCE vlans_id_seq RESTART WITH 1;
            ALTER SEQUENCE private_subnets_id_seq RESTART WITH 1;
EOF

}

function create_subnets {

x=$1
y=$2
i=0
j=0
limit=255
oct1=${x%%.*}
x=${x#*.*}
oct2=${x%%.*}
x=${x#*.*}
oct3=${x%%.*}
x=${x#*.*}
oct4=${x%%.*}

while [ "$(($oct3+$j))" -le "$limit" ]
do
    while [ "$(($oct4+$i))" -le "$limit" ]
      do
        QUERY+="INSERT INTO subnets (ip,capacity,available,parent_id) values('$oct1.$oct2.$(($oct3+$j)).$(($oct4+$i))/$y',4,4,1);"
        let i=i+4
      done
    let i=0
    let j=j+1
done

psql im << EOF
$QUERY
EOF

}

purge_db
create_subnets $1 $2