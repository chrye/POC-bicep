@description('Name of the Key Vault')
param keyVaultName string

@description('Name of the certificate')
param certificateName string

@description('The Key Vault resource group name')
param keyVaultResourceGroupName string = resourceGroup().name

@description('Content type of the certificate')
param contentType string = 'application/x-pkcs12'

resource existingKeyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
  scope: resourceGroup(keyVaultResourceGroupName)
}

resource certificate 'Microsoft.KeyVault/vaults/certificates@2023-02-01' existing = {
  name: certificateName
  parent: existingKeyVault
}

@description('Certificate secret identifier')
output secretId string = certificate.properties.secretId

@description('Certificate version identifier')
output version string = last(split(certificate.properties.secretId, '/'))

@description('Key Vault URI')
output keyVaultUri string = existingKeyVault.properties.vaultUri
