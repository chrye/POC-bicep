// filepath: c:\demo-ghcopilot\bicep\main-frontdoor.bicep
@description('Location for resources')
param location string = resourceGroup().location

@description('Front Door configurations')
param frontDoorConfigurations array

@description('Key vault configuration for TLS certificates')
param keyVaultConfiguration object = {
  keyVaultName: ''
  keyVaultResourceGroupName: resourceGroup().name
  certificateNames: []
}

@description('Common tags to apply to all resources')
param commonTags object = {}

// Get the existing KeyVault if specified
resource existingKeyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = if(!empty(keyVaultConfiguration.keyVaultName)) {
  name: keyVaultConfiguration.keyVaultName
  scope: resourceGroup(keyVaultConfiguration.keyVaultResourceGroupName)
}

// Deploy Front Door resources
module frontDoorDeployments '../modules/frontdoor/frontdoor.bicep' = [for (fdConfig, i) in frontDoorConfigurations: {
  name: 'fd-${fdConfig.name}-${i}'
  params: {
    profileName: fdConfig.name
    location: fdConfig.?location ?? location
    skuName: fdConfig.?skuName ?? 'Premium_AzureFrontDoor'
    tags: union(commonTags, fdConfig.?tags ?? {})
    originGroups: fdConfig.?originGroups ?? []
    endpoints: fdConfig.?endpoints ?? []
    routes: fdConfig.?routes ?? []
    customDomains: fdConfig.?customDomains ?? []
    keyVaultConfig: {
      keyVaultName: fdConfig.?keyVaultName ?? keyVaultConfiguration.keyVaultName
      keyVaultResourceGroupName: fdConfig.?keyVaultResourceGroupName ?? keyVaultConfiguration.keyVaultResourceGroupName
      certificateNames: fdConfig.?certificateNames ?? keyVaultConfiguration.certificateNames
      keyVaultUri: !empty(keyVaultConfiguration.keyVaultName) ? existingKeyVault.properties.vaultUri : ''
    }
  }
}]

// Output Front Door profile details
output frontDoorDetails array = [for (fdConfig, i) in frontDoorConfigurations: {
  name: frontDoorDeployments[i].outputs.profileName
  id: frontDoorDeployments[i].outputs.profileId
  endpoints: frontDoorDeployments[i].outputs.endpoints
  customDomains: frontDoorDeployments[i].outputs.customDomains
}]
