from dbutils import *

class Customer(object):
    def __init__(self):
        pass

    def get_customer(self, cus_id=None):
        customer = {'id': cus_id,
                    'ves': {},
                    'vlans': {}}

instance = Dbutils()
instance.get_all_customer()
