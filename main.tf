resource "azurerm_resource_group" "myrsg" {
  name     = format("%s-%s",var.resourcegroup,terraform.workspace)
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "myvnet" {
  name                = format("%s-%s-%s-%s", var.resourcegroup, var.location, "vnet",terraform.workspace)
  resource_group_name = azurerm_resource_group.myrsg.name
  location            = azurerm_resource_group.myrsg.location
  address_space       = ["192.168.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "mysubnet" {
  count                = length(var.subnet_cidr)
  name                 = format("%s-%s-%s-%s","subnet",azurerm_resource_group.myrsg.location,terraform.workspace,count.index+1)
  virtual_network_name = azurerm_virtual_network.myvnet.name
  resource_group_name  = azurerm_resource_group.myrsg.name
  address_prefixes     = element([var.subnet_cidr],count.index)
}

resource "azurerm_public_ip" "pip" {
  name                = format("%s-%s", "pip", terraform.workspace)
  location            = azurerm_virtual_network.myvnet.location
  resource_group_name = azurerm_resource_group.myrsg.name
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "mynic" {
  name                = format("%s-%s", "mynic", terraform.workspace)
  location            = azurerm_virtual_network.myvnet.location
  resource_group_name = azurerm_resource_group.myrsg.name

  ip_configuration {
    name                          = "mynicip"
    subnet_id                     = azurerm_subnet.mysubnet[0].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id

  }
}

resource "azurerm_network_security_group" "nsg" {
  resource_group_name = azurerm_resource_group.myrsg.name
  name                = format("%s-%s", terraform.workspace, "nsg")
  location            = azurerm_virtual_network.myvnet.location
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
  subnet_id                 = azurerm_subnet.mysubnet[0].id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_linux_virtual_machine" "myvm" {
  name                  = format("%s-%s-%s", azurerm_resource_group.myrsg.name, "mylinuxvm", terraform.workspace)
  location              = azurerm_virtual_network.myvnet.location
  resource_group_name   = azurerm_resource_group.myrsg.name
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
    command = "ansible-playbook -i ${azurerm_linux_virtual_machine.myvm.public_ip_address}, --private-key id_rsa ./httpd.yaml"
  }
}

output "public_ip" {
  value = azurerm_public_ip.pip.ip_address
}
