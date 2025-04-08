@description('Name of the Azure Container Registry')
param registryName string

@description('Location for the registry')
param location string = resourceGroup().location

@description('Enable admin user')
param adminUserEnabled bool = false

@description('SKU name')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param skuName string = 'Premium'

@description('Network rule set for ACR')
param networkRuleSet object = {
  defaultAction: 'Allow'
  ipRules: []
  virtualNetworkRules: []
}

@description('Tags for the resource')
param tags object = {}

@description('Private endpoint configuration')
param privateEndpointConfig object = {
  enabled: false
  subnetId: ''
  privateDnsZoneId: ''
  groupIds: ['registry']
}

@description('Certificate configuration')
param certificateConfig object = {
  enabled: false
  keyVaultUri: ''
  secretId: ''
  version: ''
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: registryName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    adminUserEnabled: adminUserEnabled
    networkRuleSet: networkRuleSet
    // Add certificate properties if certificate is enabled
    encryption: certificateConfig.enabled ? {
      status: 'enabled'
      keyVaultProperties: {
        identity: 'SystemAssigned'
        keyIdentifier: certificateConfig.secretId
      }
    } : null
  }
}

// Create private endpoint if enabled
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = if (privateEndpointConfig.enabled && !empty(privateEndpointConfig.subnetId)) {
  name: '${registryName}-pe'
  location: location
  tags: tags
  properties: {
    privateLinkServiceConnections: [
      {
        name: '${registryName}-connection'
        properties: {
          privateLinkServiceId: acr.id
          groupIds: privateEndpointConfig.groupIds
        }
      }
    ]
    subnet: {
      id: privateEndpointConfig.subnetId
    }
  }
}

// Create DNS zone group if private endpoint and DNS zone are specified
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = if (privateEndpointConfig.enabled && !empty(privateEndpointConfig.subnetId) && !empty(privateEndpointConfig.privateDnsZoneId)) {
  name: 'default'
  parent: privateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: privateEndpointConfig.privateDnsZoneId
        }
      }
    ]
  }
}

@description('The ACR login server')
output loginServer string = acr.properties.loginServer

@description('The ACR resource ID')
output id string = acr.id

@description('The ACR name')
output name string = acr.name

@description('The private endpoint ID, if created')
output privateEndpointId string = privateEndpointConfig.enabled && !empty(privateEndpointConfig.subnetId) ? privateEndpoint.id : ''
