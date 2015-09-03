#!/bin/bash

# CONSTANTS
# this is 4rd input parameter for script so that private_ip mask for ve will be as you with
private_ip_mask=$4

# this is for future modifications, to include logging
LOG='/tmp/vlans_resizer/operations.log'

################################################################################################################
########## FUNCTION TO PREPARE TEMP DIRECTORIES, FILES                                    ######################
################################################################################################################

# function itself creates temporary folders for appropriate scripts and for backups

function prepare {

mkdir '/tmp/vlans_resizer/'
mkdir '/tmp/vlans_resizer/rollback'
mkdir '/tmp/vlans_resizer/scripts'
mkdir '/tmp/vlans_resizer/backup'
touch '/tmp/vlans_resizer/operations.log'

}

################################################################################################################
########## FUNCTION TO MAKE IM DATABASE BACKUP                                            ######################
################################################################################################################

# function will do backup + compressing it

function backup_im_database {

pg_dump -Fc im | gzip > /tmp/vlans_resizer/backup/imdbBackup`date '+%Y%m%d%H'`.gz

}

################################################################################################################
########## FUNCTION TO PURGE DB SO WE CAN MAKE NEW VLANS AND SUBNETS                      ######################
################################################################################################################

# function creates complete query to clean old subnets,vlans,vlans_advertised + restart sequences from 1

function purge_db {


psql im << EOF
            DELETE FROM subnets;
            DELETE FROM vlans_advertised;
            DELETE FROM vlans;
            ALTER SEQUENCE vlans_id_seq RESTART WITH 1;
            ALTER SEQUENCE private_subnets_id_seq RESTART WITH 1;
EOF

}

################################################################################################################
########## FUNCTION TO UPDATE nets TABLE WITH NEW MASK, IP MAX MIN                        ######################
################################################################################################################

# function takes 1st 2nd 3rd input parameters for script as ip_min, ip_max, subnet_mask
# and only updates nets tables

function update_net {

IP_MIN=$1
IP_MAX=$2
SUBNET_MASK=$3

psql im -c "UPDATE nets SET ip_min='$IP_MIN',ip_max='$IP_MAX',subnet_mask='$SUBNET_MASK'"

}

################################################################################################################
########## FUNCTION TO CREATE SUBNETS WITH NEW MASK AND CAPACITY			              ######################
########## it took 2 input parameter from console, ip and mask, like 10.1.1.1 30 ###############################
################################################################################################################


# this fuction takes 1st 2nd 3rd input parameters and parses ip-s octets
# then we assume ip_max 3rd octet as biglimit for big loop
# if ip_max and ip_min 3rd octets are the same we took limit for small loop as 4rd ip_max octet

function create_subnets {

minip=$1
maxip=$2
mask=$3

i=0
j=0

# parser of min_ip to octets, we will iterate them

oct1=${minip%%.*}
minip=${minip#*.*}
oct2=${minip%%.*}
minip=${minip#*.*}
oct3=${minip%%.*}
minip=${minip#*.*}
oct4=${minip%%.*}


# parser of max_ip to octets, we will check that limit

oct12=${maxip%%.*}
maxip=${maxip#*.*}
oct22=${maxip%%.*}
maxip=${maxip#*.*}
oct32=${maxip%%.*}
maxip=${maxip#*.*}
oct42=${maxip%%.*}

let limit=255

if [ "$oct3" == "$oct32" ]
    then
    let limit=oct42
fi

let biglimit=oct32+1


# based on limits for 4th and 3th octets wth create appropriate chunks

while [ "$(($oct3+$j))" -lt "$biglimit" ]
do
    while [ "$(($oct4+$i))" -le "$limit" ]
      do
        QUERY+="INSERT INTO subnets (ip,capacity,available,parent_id,assigned) values('$oct1.$oct2.$(($oct3+$j)).$(($oct4+$i))/$mask',4,4,1,decode('00','hex'));"
        let i=i+4
        if [ "$(($oct3+$j))" -eq "$oct32" ]
           then
           let limit=oct42
        fi
      done
    let i=0
    let j=j+1
done

psql im << EOF
$QUERY
EOF

}

################################################################################################################
########## SIMPLE FUNCTION TO CREATE VLAN                                        	      ######################
################################################################################################################

# this fuction perform vlan creation for customer
# by design only one vlan needed for customer, but few subnets migth be assigned

function create_vlan {

psql im -c "INSERT INTO vlans (label,customer_id,version) VALUES('VLAN for customer#$CUSTOMER_ID',$CUSTOMER_ID,1) RETURNING id" --no-align --quiet --tuples-only

}


################################################################################################################
########## FUNCTION TO PERFORM ADVERTISING, VLAN CREATION, SUBNETS UPDATE                 ######################
################################################################################################################

# when we have less or equal 4 VEs for customer, we perform really simple subnet assignment
# and vlan advertisement based on ve-s location
# assigned is bytea code, representing how much ip-s of subnets are used
# 1000 0000 means 1
# 1100 0000 means 2
# 1110 0000 means 3
# etc

function assign_one_subnet {


capacity=$((4-$veNum))
rest=$(($veNum%4))

case "$rest" in 
   "0") assigned=f0
	;;
   "1") assigned=80
	;;
   "2") assigned=c0
	;;
   "3") assigned=e0
	;;
esac


VLAN_ID=`create_vlan`
IP_RANGE=`update_subnet $capacity $assigned`

echo "customer $CUSTOMER_ID with $veNum VES got subnet $SUBNET_ID and iprange $IP_RANGE"

update_private_ip

vlan_advertisement
let SUBNET_ID=SUBNET_ID+1

}

################################################################################################################
########## FUNCTION TO PERFORM ADVERTISING AND VLAN CREATION WHEN FEW VLANS NEEDED        ######################
################################################################################################################

# with multiple subnets we have a little hack
# we sould do like with one subnet, but we need iterate for subnets id-s and took ip-s from there

function assign_multiple_subnets {


numSubnets=$(($veNum/4))

echo "customer $CUSTOMER_ID with $veNum VES will got $numSubnets subnets for its vlan $VLAN_ID"

rest=$(($veNum%4))

capacity=$((4-$rest))

case "$rest" in 
   "0") assigned=f0
	;;
   "1") assigned=80
	;;
   "2") assigned=c0
	;;
   "3") assigned=e0
	;;
esac


VLAN_ID=`create_vlan`
IP_RANGE=`update_subnet 0 f0`

update_private_ip

vlan_advertisement

while [ "$numSubnets" -ge 1 ]
do
  let SUBNET_ID=SUBNET_ID+1
  IP_RANGE=`update_subnet 0 f0`
  echo "customer $CUSTOMER_ID with $veNum VES got subnet $SUBNET_ID and iprange $IP_RANGE"
  let numSubnets=numSubnets-1
done

IP_RANGE=`update_subnet $capacity $assigned`
}


################################################################################################################
########## SIMPLE FUNCTION TO UPDATE SUBNETS WITH NEW CAPACITY AND WITH ASSIGNED IP-S COUNT#####################
################################################################################################################

# simple atomic function to make capacity,assigned changes based on input parameters

function update_subnet {


psql im -c "UPDATE subnets SET vlan_id=$VLAN_ID,available=$1,assigned=decode('$2','hex') WHERE id = $SUBNET_ID RETURNING ip" --no-align --quiet --tuples-only

}

################################################################################################################
########## FUNCTION TO PARSE IP RANGE                                                     ######################
################################################################################################################

# simple atomic function made for ip address parsing and removing / from it

function parse_ip_range {


let i=0
x=`echo $IP_RANGE | sed 's/[/].*$//'`
oct1=${x%%.*}
x=${x#*.*}
oct2=${x%%.*}
x=${x#*.*}
oct3=${x%%.*}
x=${x#*.*}
oct4=${x%%.*}

}
################################################################################################################
########## FUNCTION TO UPDATE PRIVATE IP-S OF VE-S                                        ######################
################################################################################################################

# this function iterates customer's VEs and assign appropriate IP from subnets
# as we said previously, when assigning multiple subnets for customer
# this function called before we iterate subnet id
# so, we make local subnet id and get ips from there
# when we return to subnets assignment, we will took same subnets and assign them to customer vlan
# ip-s will be already updated

function update_private_ip {

LOCAL_SUBNET_ID=SUBNET_ID
parse_ip_range

psql im -c "SELECT id FROM ve where customer_id = $CUSTOMER_ID" --set ON_ERROR_STOP=on --no-align --quiet --tuples-only |
while read VE_ID;
do
  psql im -c "UPDATE ve set private_ip ='$oct1.$oct2.$oct3.$(($oct4+$i))/$private_ip_mask' WHERE id = $VE_ID"
  let i=i+1
    if [ "$i" == 4 ]
       then
       let LOCAL_SUBNET_ID=LOCAL_SUBNET_ID+1
       IP_RANGE=`psql im -c "SELECT ip FROM subnets WHERE id = $LOCAL_SUBNET_ID" --set ON_ERROR_STOP=on --no-align --quiet --tuples-only`
       parse_ip_range
    fi
done

}

################################################################################################################
########## FUNCTION TO ADVERTISE VLAN DEPENDS ON COUNT OF CUSTOMERS VES     	          ######################
################################################################################################################

# this fucntion is pretty simple
# it iterates customer's VEs and since we have only one vlan for customer
# we took it and insert into vlans_advertised table values
# because VEs could be located on many nodes, we check if record already exists
# if not, we create it
# if yes, we update subscriptions (count of VE assigned to vlan on that node)

function vlan_advertisement {


i=1
count=1

psql im -F ' ' -c "SELECT id,hn_id FROM ve where customer_id = $CUSTOMER_ID" --set ON_ERROR_STOP=on --no-align --quiet --tuples-only |
while read VE_ID HN_UUID;
do
  HNODE_ID=`psql im -c "SELECT id FROM hn WHERE uuid = '$HN_UUID'" --no-align --quiet --tuples-only`
  RESULT=`psql im -c "SELECT exists(SELECT 1 FROM vlans_advertised WHERE vlan_id = $VLAN_ID AND hnode_id = $HNODE_ID)" --no-align --quiet --tuples-only`
  if [ "$RESULT" == "f" ]
      then
      psql im -c "INSERT INTO vlans_advertised (vlan_id,hnode_id,version_advertised,subscriptions) values($VLAN_ID,$HNODE_ID,1,$count)"
      let count=count+1
  else
      let count=count+1
      psql im -c "UPDATE vlans_advertised set subscriptions=$count WHERE vlan_id=$VLAN_ID AND hnode_id=$HNODE_ID"
  fi
  echo "advertised vlan $VLAN_ID to the node $HN_UUID with subscription count $count"
done

}

################################################################################################################
########## FUNCTION TO PREPARE SCRIPTS TO BE EXECUTED ON PCS NODES                        ######################
################################################################################################################

# this is post operations function
# generates .sh script to be executed on node
# simply insert first command to remove vlans to vlans_delete.sh (same on every node)
# next it generates PCS commands to be executed
# it checks technology and make appropriate commands for VE and CT

function generate_scripts {

echo "for i in \`prlsrvctl privnet list | grep -v LEGACY | grep -v Name | awk '{print \$1}'\`; do prlsrvctl privnet del \$1; done" >> '/tmp/vlans_resizer/scripts/vlans_delete.sh'

psql im -F ' ' -c "SELECT ve.uuid,hn.name,templates.technology,ve.private_ip FROM ve INNER JOIN templates ON (ve.template_id=templates.id) INNER JOIN hn ON (ve.hn_id=hn.uuid)" --set ON_ERROR_STOP=on --no-align --quiet --tuples-only |
while read VE_UUID HARDWARE_NAME TECHNOLOGY PRIVATE_IP;
do
  if [ "$TECHNOLOGY" == "VM" ]
      then
      echo "prlctl set $VE_UUID --device-set net0 --ipdel all" >> '/tmp/vlans_resizer/scripts/'$HARDWARE_NAME.sh
      echo "prlctl set $VE_UUID --device-set net0 --ipadd $PRIVATE_IP/$private_ip_mask" >> '/tmp/vlans_resizer/scripts/'$HARDWARE_NAME.sh
  else
      echo "prlctl set $VE_UUID --device-set venet0 --ipdel all" >> '/tmp/vlans_resizer/scripts/'$HARDWARE_NAME.sh
      echo "prlctl set $VE_UUID --device-set venet0 --ipadd $PRIVATE_IP/$private_ip_mask" >> '/tmp/vlans_resizer/scripts/'$HARDWARE_NAME.sh
  fi
done

}

################################################################################################################
########## FUNCTION TO PREPARE SCRIPTS TO MAKE CHANGES BACK ON  PCS NODES                 ######################
################################################################################################################

# this is pre operations function
# generates .sh script to be executed on node in case you will need to revert changes on containers
# it checks technology and make appropriate commands for VE and CT

function generate_rollback {

old_private_ip_mask=`psql im -c "SELECT mask FROM nets" --no-align --quiet --tuples-only`

psql im -F ' ' -c "SELECT ve.uuid,hn.name,templates.technology,ve.private_ip FROM ve INNER JOIN templates ON (ve.template_id=templates.id) INNER JOIN hn ON (ve.hn_id=hn.uuid)" --set ON_ERROR_STOP=on --no-align --quiet --tuples-only |
while read VE_UUID HARDWARE_NAME TECHNOLOGY PRIVATE_IP;
do
  if [ "$TECHNOLOGY" == "VM" ]
      then
      echo "prlctl set $VE_UUID --device-set net0 --ipdel all" >> '/tmp/vlans_resizer/rollback/'$HARDWARE_NAME.sh
      echo "prlctl set $VE_UUID --device-set net0 --ipadd $PRIVATE_IP/$old_private_ip_mask" >> '/tmp/vlans_resizer/rollback/'$HARDWARE_NAME.sh
  else
      echo "prlctl set $VE_UUID --device-set venet0 --ipdel all" >> '/tmp/vlans_resizer/rollback/'$HARDWARE_NAME.sh
      echo "prlctl set $VE_UUID --device-set venet0 --ipadd $PRIVATE_IP/$old_private_ip_mask" >> '/tmp/vlans_resizer/rollback/'$HARDWARE_NAME.sh
  fi
done

}

################################################################################################################
########## STEP #1 - DELETING OF OLD DB DATA AND RECREATING OF VLANS     	          ######################
################################################################################################################

echo "STAGE #1 - PREPARING FOLDERS"
prepare
echo "STAGE #1 - FINISHED"

echo "STAGE #2 - PREPARING ROLLBACK SCRIPTS GENERATING"
generate_rollback
echo "STAGE #2 - FINISHED"

echo "STAGE #3 - PREPARING IM DATABASE BACKUP"
backup_im_database
echo "STAGE #3 - FINISHED"

echo "STAGE #4 - PREPARING UPDATE NETS WITH NEW IP MIN MAX MASK"
update_net $1 $2 $3
echo "STAGE #4 - FINISHED"

echo "STAGE #5 - PREPARING CLEAN UP DB VLANS TABLES"
purge_db
echo "STAGE #5 - FINISHED"

sleep 10

echo "STAGE #6 - PREPARING NEW SUBNETS"
create_subnets $1 $2 $3
echo "STAGE #6 - FINISHED"

################################################################################################################
########## STEP #2 - GETTING LIST OF CUSTOMERS                           	              ######################
################################################################################################################

echo "STAGE #7 - MAIN OPERATIONS VLAN CREATION SUBNETS ASSIGNMENT ADVERTISEMENT"
SUBNET_ID=1

psql im -c "SELECT id FROM customers" --set ON_ERROR_STOP=on --no-align --quiet --tuples-only |
while read CUSTOMER_ID ;
do


   # we checking the numbers of ve per customer and performing vlans creation and subnet adjustments appropriatelly

    veNum=`psql im -c "SELECT COUNT(*) FROM ve WHERE customer_id = $CUSTOMER_ID" --no-align --quiet --tuples-only`
    case "$veNum" in
      "0")


################################################################################################################
########## STEP #3 - SPECIAL CASE WHEN NO VE-S FOR CUSTOMER, WE ONLY CREATE EMPTY VLAN    ######################
################################################################################################################

   # the first step is to create vlan id and get it into variable
           VLAN_ID=`create_vlan`

   # no need to update subnets when 0 VM-s for customer
           let SUBNET_ID=SUBNET_ID+1
		 ;;


################################################################################################################
########## STEP #4 - TWO CASES: 1 SUBNET NEEDED OR N-SUBNETS                              ######################
################################################################################################################

      [1-4]|4)
           assign_one_subnet
		 ;;
      [5-9]|1[0-9]|20)
           assign_multiple_subnets
		 ;;
   esac
done

echo "STAGE #8 - FINISHED"

echo "STAGE #9 - POST SCRIPTS GENERATION"
generate_scripts
echo "STAGE #9 - FINISHED"


