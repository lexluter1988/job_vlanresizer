import psycopg2
import psycopg2.extras
import xml.etree.ElementTree as ET

class ChangeBackup(object):
    def __init__(self, connection=None):
        self.connection = connection

    def get_backup_config(self):

        # connecting to IM database and getting ve_config from ve_backup table
        try:
            connection = psycopg2.connect("dbname='im' user='postgres'",
                                          connection_factory=psycopg2.extras.RealDictConnection)
            cur = connection.cursor()
            cur.execute("SELECT ve_ref, ve_config FROM ve_backups WHERE ve_ref IS NOT NULL limit 1")
            configs = cur.fetchall()
            cur.close()
            connection.close()

        except psycopg2.Error as e:
            print e.pgerror
            return 1

        # next we getting dict of ve_config and taking uuid and private ip from there
        # this is xml object we can work with
        ve_ref = configs[0]['ve_ref']
        xml_config = configs[0]['ve_config']
        print xml_config

        # it also our root of xml, comparing with reading from file
        root = ET.fromstring(xml_config)
        ve_uuid = root.find('uuid').text

        # one more connecting to IM database and getting new ip, which set after vlans resizing
        try:
            connection = psycopg2.connect("dbname='im' user='postgres'",
                                          connection_factory=psycopg2.extras.RealDictConnection)
            cur = connection.cursor()
            cur.execute("SELECT private_ip FROM ve WHERE uuid = '%s';" % ve_uuid)
            new_private_ip = cur.fetchall()
            cur.close()
            connection.close()
            new_private_ip = new_private_ip[0]['private_ip']

        except psycopg2.Error as e:
            print e.pgerror
            return 1

        print ve_ref
        print ve_uuid
        print new_private_ip
        for child in root.findall('network'):
            ip_before = child.get('private-ip')
            print ip_before
            child.set('private-ip', new_private_ip)
            ip_after = child.get('private-ip')
            print ip_after
        new_xml_config = ET.tostring(root, encoding="utf8", method="xml")
        new_xml_config = new_xml_config.replace('<?xml version=\'1.0\' encoding=\'utf8\'?>',
                                                '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
        print new_xml_config

        # last connection to db to update ve_backups ve_configration with new ip
        try:
            connection = psycopg2.connect("dbname='im' user='postgres'",
                                          connection_factory=psycopg2.extras.RealDictConnection)
            cur = connection.cursor()
            cur.execute("UPDATE ve_backups SET ve_config = '%s' WHERE ve_ref = '%s';" % (new_xml_config, ve_ref))
            connection.commit()
            cur.close()
            connection.close()

        except psycopg2.Error as e:
            print e.pgerror
            return 1

conn = ChangeBackup()
conn.get_backup_config()
