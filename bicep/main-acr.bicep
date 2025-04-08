@description('Location for the resources')
param location string = resourceGroup().location

@description('Array of ACR configurations to deploy')
param acrConfigurations array

@description('Virtual network details for ACR integration')
param vnetConfiguration object = {
  vnetName: ''
  vnetResourceGroupName: resourceGroup().name
  subnetName: ''
}

@description('Key vault details for certificate integration, if needed')
param keyVaultConfiguration object = {
  keyVaultName: ''
  keyVaultResourceGroupName: resourceGroup().name
  certificateName: ''
}

@description('Private DNS zone ID for ACR private endpoints')
param privateDnsZoneId string = ''

@description('Common tags to apply to all resources')
param commonTags object = {}

// Get the existing VNet if specified
resource existingVNet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = if(!empty(vnetConfiguration.vnetName)) {
  name: vnetConfiguration.vnetName
  scope: resourceGroup(vnetConfiguration.vnetResourceGroupName)
}

// Get the subnet from the VNet if specified
var subnetId = !empty(vnetConfiguration.vnetName) && !empty(vnetConfiguration.subnetName) ? '${existingVNet.id}/subnets/${vnetConfiguration.subnetName}' : ''
var vnetRules = !empty(subnetId) ? [
  {
    id: subnetId
    action: 'Allow'
  }
] : []

// Get certificate from Key Vault if specified
module certificate '../modules/keyvault/certificate.bicep' = if(!empty(keyVaultConfiguration.keyVaultName) && !empty(keyVaultConfiguration.certificateName)) {
  name: 'certificate-${keyVaultConfiguration.certificateName}'
  params: {
    keyVaultName: keyVaultConfiguration.keyVaultName
    keyVaultResourceGroupName: keyVaultConfiguration.keyVaultResourceGroupName
    certificateName: keyVaultConfiguration.certificateName
  }
}

// Set up certificate configuration object
var certificateConfig = !empty(keyVaultConfiguration.keyVaultName) && !empty(keyVaultConfiguration.certificateName) ? {
  enabled: true
  keyVaultUri: certificate.outputs.keyVaultUri
  secretId: certificate.outputs.secretId
  version: certificate.outputs.version
} : {
  enabled: false
  keyVaultUri: ''
  secretId: ''
  version: ''
}

// Set up private endpoint configuration object
var privateEndpointConfig = !empty(subnetId) ? {
  enabled: true
  subnetId: subnetId
  privateDnsZoneId: privateDnsZoneId
  groupIds: ['registry']
} : {
  enabled: false
  subnetId: ''
  privateDnsZoneId: ''
  groupIds: ['registry']
}

// Deploy ACRs based on the provided configurations
module acrs '../modules/acr/acr.bicep' = [for (acrConfig, i) in acrConfigurations: {
  name: 'acr-${acrConfig.name}-${i}'
  params: {
    registryName: acrConfig.name
    location: acrConfig.?location ?? location
    skuName: acrConfig.?skuName ?? 'Premium'
    adminUserEnabled: acrConfig.?adminUserEnabled ?? false
    tags: union(commonTags, acrConfig.?tags ?? {})
    networkRuleSet: {
      defaultAction: (acrConfig.?allowPublicAccess ?? false) ? 'Allow' : 'Deny'
      virtualNetworkRules: vnetRules
      ipRules: acrConfig.?ipRules ?? []
    }
    privateEndpointConfig: acrConfig.?privateEndpoint ?? privateEndpointConfig
    certificateConfig: acrConfig.?certificate ?? certificateConfig
  }
}]

// Output the ACR details
output acrDetails array = [for (acrConfig, i) in acrConfigurations: {
  name: acrs[i].outputs.name
  loginServer: acrs[i].outputs.loginServer
  id: acrs[i].outputs.id
  privateEndpointId: acrs[i].outputs.?privateEndpointId ?? ''
}]
