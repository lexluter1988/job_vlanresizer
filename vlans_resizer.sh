#!/bin/bash
################################################################################################################
########## FUNCTION TO PURDE EXISTING VLAN,SUBNETS,VLANS_AVERTISED, AND RESTART SEQUENCES ######################
################################################################################################################

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

################################################################################################################
########## FUNCTION TO RECREATE SUBNETS WITH NEW MASK AND CAPACITY			  ######################
########## it took 2 input parameter from console, ip and mask, like 10.1.1.1 30 ###############################
################################################################################################################

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

################################################################################################################
########## SIMPLE FUNCTION TO CREATE VLAN, INCLUDED IN MORE COMPLICATED FUNCTION	      ######################
################################################################################################################

function create_vlan {

psql im -c "INSERT INTO vlans (label,customer_id,version) VALUES('VLAN for customer#$CUSTOMER_ID',$CUSTOMER_ID,1) RETURNING id" --no-align --quiet --tuples-only
}


################################################################################################################
########## FUNCTION TO PERFORM ADVERTISING AND VLAN CREATION                              ######################
################################################################################################################


function create_one_vlan {

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
echo "$veNum VMs, updating ve table with ip of subnet"        
update_private_ip           
echo "updating vlans_advertised table $VLAN_ID $HNODE_ID"
vlan_advertisement
let SUBNET_ID=SUBNET_ID+1
   
}

################################################################################################################
########## FUNCTION TO PERFORM ADVERTISING AND VLAN CREATION WHEN FEW VLANS NEEDED        ######################
################################################################################################################

function create_multiple_vlans {

numSubnets=$(($veNum/4))
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
echo "updating vlans_advertised table $VLAN_ID $HNODE_ID"
vlan_advertisement

while [ "$numSubnets" -ge 1 ]
do
  let SUBNET_ID=SUBNET_ID+1
  IP_RANGE=`update_subnet 0 f0`
  let numSubnets=numSubnets-1
done

IP_RANGE=`update_subnet $capacity $assigned`
}


################################################################################################################
########## SIMPLE FUNCTION TO UPDATE SUBNETS WITH NEW CAPACITY AND WITH ASSIGNED IP-S COUNT#####################
################################################################################################################

function update_subnet {

psql im -c "UPDATE subnets SET vlan_id=$VLAN_ID,available=$1,assigned=decode('$2','hex') WHERE id = $SUBNET_ID RETURNING ip" --no-align --quiet --tuples-only
}

################################################################################################################
########## FUNCTION TO PARSE IP RANGE                                                     ######################
################################################################################################################

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

function update_private_ip {

LOCAL_SUBNET_ID=SUBNET_ID

parse_ip_range

psql im -F ' ' -c "SELECT id,uuid,hn_id,private_ip FROM ve where customer_id = $CUSTOMER_ID" --set ON_ERROR_STOP=on --no-align --quiet --tuples-only |
while read VE_ID UUID HNODE_ID IP;
do
  echo "assigning for $VE_ID IP address = $oct1.$oct2.$oct3.$((oct4+$i))/8"
  psql im -c "UPDATE ve set private_ip ='$oct1.$oct2.$oct3.$(($oct4+$i))/8' WHERE id = $VE_ID"
  HNAME=`psql im -c "SELECT name FROM hn WHERE id = $HNODE_ID" --no-align --quiet --tuples-only`
  echo "prlctl set $UUID --device-set venet0 --ipdel all" >> $HNAME.sh
  echo "prlctl set $UUID --device-set venet0 --ipadd $IP" >> $HNAME.sh
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

function vlan_advertisement {

i=1
count=1

psql im -F ' ' -c "SELECT id,hn_id FROM ve where customer_id = $CUSTOMER_ID" --set ON_ERROR_STOP=on --no-align --quiet --tuples-only |
while read VE_ID HNODE_ID;
do
  RESULT=`psql im -c "SELECT exists(SELECT 1 FROM vlans_advertised WHERE vlan_id = $VLAN_ID AND hnode_id = $HNODE_ID)" --no-align --quiet --tuples-only`
  if [ "$RESULT" == "f" ]
      then
      psql im -c "INSERT INTO vlans_advertised (vlan_id,hnode_id,version_advertised,subscriptions) values($VLAN_ID,$HNODE_ID,1,$count)"
      let count=count+1
  else
      let count=count+1
      psql im -c "UPDATE vlans_advertised set subscriptions=$count WHERE vlan_id=$VLAN_ID AND hnode_id=$HNODE_ID"
  fi
done
}

################################################################################################################
########## STEP #1 - DELETING OF OLD DB DATA AND RECREATING OF VLANS     	          ######################
################################################################################################################

purge_db
sleep 10
create_subnets $1 $2

################################################################################################################
########## STEP #2 - GETTING LIST OF CUSTOMERS                           	          ######################
################################################################################################################

echo "assuming we assigning subnets from the first one"

SUBNET_ID=1

echo "getting all id-s of customers"

psql im -c "SELECT id FROM customers" --set ON_ERROR_STOP=on --no-align --quiet --tuples-only |
while read CUSTOMER_ID ; 
do
   echo "VLAN for customer#$CUSTOMER_ID"

   # we checking the numbers of ve per customer and performing vlans creation and subnet adjustments appropriatelly

   veNum=`psql im -c "SELECT COUNT(*) FROM ve WHERE customer_id = $CUSTOMER_ID" --no-align --quiet --tuples-only`
   case "$veNum" in
      "0") 


################################################################################################################
########## STEP #3 - SPECIAL CASE WHEN NO VE-S FOR CUSTOMER, WE ONLY CREATE EMPTY VLAN    ######################
################################################################################################################

   # the first step is to create vlan id and get it into variable
           VLAN_ID=`create_vlan`
           echo "creating first vlan $CUSTOMER_ID $VLAN_ID"

   # no need to update subnets when 0 VM-s for customer
           echo "this is 0 VM-s subnet, not need to update ve table"
           let SUBNET_ID=SUBNET_ID+1
		;;


################################################################################################################
########## STEP #4 - TWO CASES: 1 VLAN NEEDED OR N-VLANS                                  ######################
################################################################################################################

      [1-4]*)
           create_one_vlan 
		;;
      [5-20]*)
           create_multiple_vlans
		;;
   esac
done
