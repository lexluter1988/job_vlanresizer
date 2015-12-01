import psycopg2
import psycopg2.extras
import xml.etree.ElementTree as ET
import sys

try:
    connection = psycopg2.connect("dbname='im' user='postgres'",
                                  connection_factory=psycopg2.extras.RealDictConnection)
    cur = connection.cursor()
    cur.execute("SELECT data FROM ve_archive WHERE ve_id = 12688")
    configs = cur.fetchall()
    cur.close()
    connection.close()

except psycopg2.Error as e:
    print e.pgerror
    sys.exit(1)

print """
        ############   problematic config" ############
        """
print configs[0]['data']

tree = ET.parse('newxml')
root = tree.getroot()
new_xml_config = ET.tostring(root, encoding="utf8")

print """
        ############   correct config" ############
        """
new_xml_config = new_xml_config.replace('<?xml version=\'1.0\' encoding=\'utf8\'?>',
                                         '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
print new_xml_config

# last connection to db to update ve_backups ve_configration with new ip
try:
    connection = psycopg2.connect("dbname='im' user='postgres'",
                                  connection_factory=psycopg2.extras.RealDictConnection)
    cur = connection.cursor()
    cur.execute("UPDATE ve_archive SET data = '%s' WHERE ve_id = 12688;" % new_xml_config)
    connection.commit()
    cur.close()
    connection.close()

except psycopg2.Error as e:
    print e.pgerror
    sys.exit(1)


print """
        ############   problem entry fixed" ############
        """