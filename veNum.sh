#!/bin/bash
echo "assuming we assigning subnets from the first one"

#SUBNET_ID=1

echo "getting all id-s of customers"

psql im -c "SELECT id FROM customers" --set ON_ERROR_STOP=on --no-align --quiet --tuples-only |
while read CUSTOMER_ID ;
do
   #echo "VLAN for customer#$CUSTOMER_ID"

   # we checking the numbers of ve per customer and performing vlans creation and subnet adjustments appropriatelly

   veNum=`psql im -c "SELECT COUNT(*) FROM ve WHERE customer_id = $CUSTOMER_ID" --no-align --quiet --tuples-only`
   case "$veNum" in
      "0")
           echo "CASE 0 : $CUSTOMER_ID has: $veNum VEs"


################################################################################################################
########## STEP #3 - SPECIAL CASE WHEN NO VE-S FOR CUSTOMER, WE ONLY CREATE EMPTY VLAN    ######################
################################################################################################################

   # the first step is to create vlan id and get it into variable
           #VLAN_ID=`create_vlan`
           #echo "creating first vlan $CUSTOMER_ID $VLAN_ID"

   # no need to update subnets when 0 VM-s for customer
           #echo "this is 0 VM-s subnet, not need to update ve table"
           #let SUBNET_ID=SUBNET_ID+1
		;;


################################################################################################################
########## STEP #4 - TWO CASES: 1 VLAN NEEDED OR N-VLANS                                  ######################
################################################################################################################

      [1-4]*)
           #create_one_vlan
           echo "CASE 1-4 $CUSTOMER_ID has: $veNum VEs"
		;;
      [5-20]*)
           echo "CASE 5-20 $CUSTOMER_ID has: $veNum VEs"
           #create_multiple_vlans
		;;
   esac
done