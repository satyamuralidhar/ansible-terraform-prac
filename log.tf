data "azurerm_network_watcher" "test" {
  name                ="NetworkWatcher_eastus"
  resource_group_name = data.azurerm_resource_group.log.name
}

data "azurerm_resource_group" "log" {
  name = "NetworkWatcherRG"
}

resource "azurerm_storage_account" "test" {
  name                = "accdevsa"
  resource_group_name = azurerm_resource_group.myrsg.name
  location            = azurerm_resource_group.myrsg.location

  account_tier              = "Standard"
  account_kind              = "StorageV2"
  account_replication_type  = "LRS"
  enable_https_traffic_only = true
}

resource "azurerm_log_analytics_workspace" "test" {
  name                = "accdevlaw"
  location            = data.azurerm_resource_group.log.location
  resource_group_name = data.azurerm_resource_group.log.name
  sku                 = "PerGB2018"
}


resource "azurerm_network_watcher_flow_log" "test" {
  network_watcher_name = data.azurerm_network_watcher.test.name
  resource_group_name  = data.azurerm_resource_group.log.name
  name                 = "example-log"

  network_security_group_id = azurerm_network_security_group.nsg.id
  storage_account_id        = azurerm_storage_account.test.id
  enabled                   = true

  retention_policy {
    enabled = true
    days    = 7
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.test.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.test.location
    workspace_resource_id = azurerm_log_analytics_workspace.test.id
    interval_in_minutes   = 10
  }
}
