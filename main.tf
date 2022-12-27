data "azurerm_resource_group" "rsg" {
  name = "ansiblersg"
}

data "azurerm_virtual_network" "vnet" {
  name                = "ansiblersg-vnet"
  resource_group_name = data.azurerm_resource_group.rsg.name
}

data "azurerm_subnet" "subnet" {
  name                 = "default"
  virtual_network_name = data.azurerm_virtual_network.vnet.name
  resource_group_name  = data.azurerm_resource_group.rsg.name
}

output "subnet_id" {
  value = data.azurerm_subnet.subnet.id
}

resource "azurerm_route_table" "myrt" {
  name = "internet-rt"
  resource_group_name = data.azurerm_resource_group.rsg.name
  location = data.azurerm_virtual_network.vnet.location

  route {
    address_prefix = "0.0.0.0/0"
    name = "route1"
    next_hop_type = "Internet"
  }

}

resource "azurerm_subnet_route_table_association" "rtassociation" {
  subnet_id = data.azurerm_subnet.subnet.id
  route_table_id = azurerm_route_table.myrt.id
}

resource "azurerm_public_ip" "pip" {
  name                = format("%s-%s", "pip", terraform.workspace)
  location            = data.azurerm_virtual_network.vnet.location
  resource_group_name = data.azurerm_resource_group.rsg.name
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "mynic" {
  name                = format("%s-%s", "mynic", terraform.workspace)
  location            = data.azurerm_virtual_network.vnet.location
  resource_group_name = data.azurerm_resource_group.rsg.name

  ip_configuration {
    name                          = "mynicip"
    subnet_id                     = data.azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id

  }
}

resource "azurerm_network_security_group" "nsg" {
  resource_group_name = data.azurerm_resource_group.rsg.name
  name                = format("%s-%s", terraform.workspace, "nsg")
  location            = data.azurerm_virtual_network.vnet.location
  dynamic "security_rule" {
    for_each = var.nsg_rules
    content {
      name                       = security_rule.value["name"]
      priority                   = security_rule.value["priority"]
      direction                  = security_rule.value["direction"]
      access                     = security_rule.value["access"]
      protocol                   = security_rule.value["protocol"]
      source_port_range          = security_rule.value["source_port_range"]
      destination_port_range     = security_rule.value["destination_port_range"]
      source_address_prefix      = security_rule.value["source_address_prefix"]
      destination_address_prefix = security_rule.value["destination_address_prefix"]
    }
  }
}
resource "azurerm_network_interface_security_group_association" "nicassociation" {
  network_interface_id      = azurerm_network_interface.mynic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_subnet_network_security_group_association" "nsgassociation" {
  subnet_id                 = data.azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_linux_virtual_machine" "myvm" {
  name                  = format("%s-%s-%s", data.azurerm_resource_group.rsg.name, "mylinuxvm", terraform.workspace)
  location              = data.azurerm_virtual_network.vnet.location
  resource_group_name   = data.azurerm_resource_group.rsg.name
  size                  = "Standard_B1s"
  admin_username        = "satya"
  network_interface_ids = [azurerm_network_interface.mynic.id]

  admin_ssh_key {
    username   = "satya"
    public_key = file("id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "RedHat"
    offer     = "RHEL"
    sku       = "79-gen2"
    version   = "latest"
  }

  provisioner "remote-exec" {
    inline = [
      file("config.tpl")
    ]
    connection {
      type        = "ssh"
      user        = "satya"
      private_key = file("./id_rsa")
      host        = azurerm_linux_virtual_machine.myvm.public_ip_address
    }
  }
  provisioner "local-exec" {
    command = "chmod 400 ./id_rsa"
  }
  provisioner "local-exec" {
    command = "ansible-playbook -i ${azurerm_linux_virtual_machine.myvm.public_ip_address}, --private-key id_rsa -vvv ./httpd.yaml"
  }
}

output "public_ip" {
  value = azurerm_public_ip.pip.ip_address
}
