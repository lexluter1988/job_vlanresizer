class Net(object):
    def __init__(self):
        pass

    def get_net(self):
        pass

    def change_net(self):
        pass


class Vlan(object):
    def __init__(self):
        pass

    def create_vlan(self):
        pass

    def delete_vlan(self):
        pass

    def get_vlan(self):
        pass

    def advertise_vlan(self):
        pass


class Subnet(object):
    def __init__(self):
        pass

    def create_subnet(self):
        pass

    def delete_subnet(self):
        pass

    def get_subnet(self):
        pass

    def change_subnet(self):
        pass


class Ve(object):
    def __init__(self):
        self.veid = veid


    def get_ve(self):
        ve = {'id': veid,
              'uuid': uuid,
              'hn_id': hn_id,
              'customer_id': customer_id,
              'is_lb': is_lb,
              'technology': technology,
              'private_ip': private_ip}
        pass

    def change_ve_address(self):
        pass


class Customer(object):
    def __init__(self):
        pass

    def get_customer(self, cus_id=None):
        customer = {'id': cus_id,
                    'ves': {},
                    'vlans': {}}
        pass

