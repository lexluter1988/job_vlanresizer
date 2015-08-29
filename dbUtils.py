# Small script to show PostgreSQL and Pyscopg together
import psycopg2


class Dbutils(object):

        def __init__(self, connection=None):
                self.connection = connection

        def connect(self):
                try:
                    connection = psycopg2.connect("dbname='im' user='postgres'")
                except:
                    print "I am unable to connect to the database"
                print "I am connected"
                return connection

        def test(self):
                print "Tested"

con = Dbutils()
con.connect()