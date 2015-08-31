import psycopg2


class Dbutils(object):
    def __init__(self, connection=None):
        self.connection = connection

    def clean_up(self):
        try:
            connection = psycopg2.connect("dbname='im' user='postgres'")
            cur = connection.cursor()
            cur.execute("""INSERT INTO vlans(label,customer_id,version) values('VLAN for customer666','1287565','1')""")
            connection.commit()
            cur.close()
            connection.close()

        except psycopg2.Error as e:
            print e.pgerror
            return 1
        print "I am connected"
        return connection

    def get_all_customer(self):
        try:
            connection = psycopg2.connect("dbname='im' user='postgres'")
            cur = connection.cursor()
            cur.execute("""SELECT name FROM ve where customer_id = 5
                        """)
            rows = cur.fetchall()
            print rows
        except psycopg2.Error as e:
            print e.pgerror
            return 1

    def test(self):
        print "Tested"