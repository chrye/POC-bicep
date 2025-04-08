@description('Name of the Virtual Network')
param vnetName string

@description('Location for the VNet')
param location string = resourceGroup().location

@description('Address space for the VNet')
param addressSpace object = {
  addressPrefixes: [
    '10.0.0.0/16'
  ]
}

@description('Array of subnets in the VNet')
param subnets array = []

@description('Tags for the resource')
param tags object = {}

resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: addressSpace
    subnets: [for subnet in subnets: {
      name: subnet.name
      properties: {
        addressPrefix: subnet.addressPrefix
        serviceEndpoints: contains(subnet, 'serviceEndpoints') ? subnet.serviceEndpoints : null
        privateEndpointNetworkPolicies: contains(subnet, 'privateEndpointNetworkPolicies') ? subnet.privateEndpointNetworkPolicies : null
        delegations: contains(subnet, 'delegations') ? subnet.delegations : null
      }
    }]
  }
}

@description('The VNet ID')
output id string = vnet.id

@description('The VNet name')
output name string = vnet.name

@description('Subnet resources')
output subnets array = [for subnet in subnets: {
  id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, subnet.name)
  name: subnet.name
}]
