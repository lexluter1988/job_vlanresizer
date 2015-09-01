from dbutils import *

class Customer(object):
    def __init__(self):
        pass

    def get_customer(self, cus_id=None):
        customer = [{'id': cus_id,
                    'ves': {},
                    'vlans': {}}]

customer = [{'id': '',
            'ves': {},
            'vlans': {}}]

instance = Dbutils()
ve = instance.get_all_customer()
for row in ve:
    customer.append({'id': row['uuid'],
                    'ves': row['hn_id'],
                    'vlans': row['name']})
print customer
