import psycopg2
import psycopg2.extras
import xml.etree.ElementTree as ET

class ChangeBackup(object):
    def __init__(self, connection=None):
        self.connection = connection

    def get_backup_config(self):
        try:
            connection = psycopg2.connect("dbname='im' user='postgres'",
                                          connection_factory=psycopg2.extras.RealDictConnection)
            cur = connection.cursor()
            cur.execute("""SELECT ve_ref, ve_config FROM ve_backups WHERE ve_ref IS NOT NULL limit 1
                        """)
            configs = cur.fetchall()

            cur.execute("""SELECT private_ip FROM ve WHERE uuid = 'd6052e15-3ee8-49ff-a705-9d44ab4bcf0a'
                        """)
            new_private_ip = cur.fetchall()

            cur.close()
            connection.close()

            xml_config = configs[0]['ve_config']

            root = ET.fromstring(xml_config)

            ve_uuid = root.find('uuid').text

            print ve_uuid

            new_private_ip = new_private_ip[0]['private_ip']

            print new_private_ip

            cur.close()
            connection.close()

            for child in root.findall('network'):
                ip_before = child.get('private-ip')
                print ip_before
                child.set('private-ip', new_private_ip)
                ip_after = child.get('private-ip')
                print ip_after

        except psycopg2.Error as e:
            print e.pgerror
            return 1


conn = ChangeBackup()
conn.get_backup_config()
