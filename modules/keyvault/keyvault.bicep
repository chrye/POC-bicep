@description('Name of the Key Vault')
param keyVaultName string

@description('Location for the Key Vault')
param location string = resourceGroup().location

@description('Tenant ID for the Key Vault')
param tenantId string = subscription().tenantId

@description('SKU name')
@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'

@description('Access policies for the Key Vault')
param accessPolicies array = []

@description('Network ACLs for the Key Vault')
param networkAcls object = {
  defaultAction: 'Allow'
  bypass: 'AzureServices'
  ipRules: []
  virtualNetworkRules: []
}

@description('Enable Key Vault for deployment?')
param enabledForDeployment bool = false

@description('Enable Key Vault for disk encryption?')
param enabledForDiskEncryption bool = false

@description('Enable Key Vault for template deployment?')
param enabledForTemplateDeployment bool = true

@description('Soft delete retention in days')
param softDeleteRetentionInDays int = 90

@description('Tags for the resource')
param tags object = {}

resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: skuName
    }
    accessPolicies: accessPolicies
    enabledForDeployment: enabledForDeployment
    enabledForDiskEncryption: enabledForDiskEncryption
    enabledForTemplateDeployment: enabledForTemplateDeployment
    softDeleteRetentionInDays: softDeleteRetentionInDays
    networkAcls: networkAcls
  }
}

@description('The Key Vault ID')
output id string = keyVault.id

@description('The Key Vault name')
output name string = keyVault.name

@description('The Key Vault URI')
output vaultUri string = keyVault.properties.vaultUri
