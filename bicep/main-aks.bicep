// filepath: c:\demo-ghcopilot\bicep\main-aks.bicep
@description('Location for resources')
param location string = resourceGroup().location

@description('AKS configurations')
param aksConfigurations array = []

@description('Virtual network configuration')
param vnetConfiguration object = {
  vnetName: ''
  vnetResourceGroupName: resourceGroup().name
  subnetName: ''
}

@description('ACR configuration')
param acrConfiguration object = {
  acrName: ''
  acrResourceGroupName: resourceGroup().name
}

@description('Key vault configuration for secrets')
param keyVaultConfiguration object = {
  keyVaultName: ''
  keyVaultResourceGroupName: resourceGroup().name
  secretNames: []  // List of secret names to retrieve
}

@description('SQL Server details for integration')
param sqlConfiguration object = {
  sqlServerName: ''
  sqlServerResourceGroupName: resourceGroup().name
}

@description('Storage Account details for integration')
param storageConfiguration object = {
  storageAccountName: ''
  storageAccountResourceGroupName: resourceGroup().name
}

@description('Managed identities configuration')
param managedIdentitiesConfig object = {
  createIdentities: true
  clusterIdentity: {
    name: ''
    resourceGroupName: resourceGroup().name
  }
  acrIdentity: {
    name: ''
    resourceGroupName: resourceGroup().name
  }
  keyVaultIdentity: {
    name: ''
    resourceGroupName: resourceGroup().name
  }
  sqlIdentity: {
    name: ''
    resourceGroupName: resourceGroup().name
  }
  storageIdentity: {
    name: ''
    resourceGroupName: resourceGroup().name
  }
}

@description('Common tags to apply to all resources')
param commonTags object = {}

// Reference existing ACR if specified
resource existingAcr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = if (!empty(acrConfiguration.acrName)) {
  name: acrConfiguration.acrName
  scope: resourceGroup(acrConfiguration.acrResourceGroupName)
}

// Reference existing Key Vault if specified
resource existingKeyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = if (!empty(keyVaultConfiguration.keyVaultName)) {
  name: keyVaultConfiguration.keyVaultName
  scope: resourceGroup(keyVaultConfiguration.keyVaultResourceGroupName)
}

// Get Key Vault secrets in a loop if specified
var keyVaultSecrets = !empty(keyVaultConfiguration.keyVaultName) && !empty(keyVaultConfiguration.secretNames) ? [for secretName in keyVaultConfiguration.secretNames: {
  name: secretName
  value: existingKeyVault.getSecret(secretName)
}] : []

// Deploy AKS clusters
module aksDeployments '../modules/aks/aks.bicep' = [for (aksConfig, i) in aksConfigurations: {
  name: 'aks-${aksConfig.name}-${i}'
  params: {
    clusterName: aksConfig.name
    location: aksConfig.?location ?? location
    kubernetesVersion: aksConfig.?kubernetesVersion ?? '1.28.3'
    tags: union(commonTags, aksConfig.?tags ?? {})
    vnetConfiguration: {
      vnetName: aksConfig.?vnetName ?? vnetConfiguration.vnetName
      vnetResourceGroupName: aksConfig.?vnetResourceGroupName ?? vnetConfiguration.vnetResourceGroupName
      subnetName: aksConfig.?subnetName ?? vnetConfiguration.subnetName
    }
    acrConfiguration: {
      acrName: aksConfig.?acrName ?? acrConfiguration.acrName
      acrResourceGroupName: aksConfig.?acrResourceGroupName ?? acrConfiguration.acrResourceGroupName
      acrId: !empty(acrConfiguration.acrName) ? existingAcr.id : ''
    }
    keyVaultConfiguration: {
      keyVaultName: aksConfig.?keyVaultName ?? keyVaultConfiguration.keyVaultName
      keyVaultResourceGroupName: aksConfig.?keyVaultResourceGroupName ?? keyVaultConfiguration.keyVaultResourceGroupName
      secrets: keyVaultSecrets
    }
    podCidr: aksConfig.?podCidr ?? '10.244.0.0/16'
    serviceCidr: aksConfig.?serviceCidr ?? '10.0.0.0/16'
    dnsServiceIP: aksConfig.?dnsServiceIP ?? '10.0.0.10'
    dockerBridgeCidr: aksConfig.?dockerBridgeCidr ?? '172.17.0.1/16'
    systemNodePool: aksConfig.?systemNodePool ?? {
      name: 'system'
      count: 3
      vmSize: 'Standard_D4s_v3'
      osDiskSizeGB: 128
      osDiskType: 'Managed'
      maxPods: 30
      minCount: 3
      maxCount: 5
      enableAutoScaling: true
    }
    userNodePools: aksConfig.?userNodePools ?? []
    enableWorkloadIdentity: aksConfig.?enableWorkloadIdentity ?? true
    addonProfiles: aksConfig.?addonProfiles ?? {}
    managedIdentitiesConfig: managedIdentitiesConfig
  }
}]

// Output AKS cluster details
output aksDetails array = [for (aksConfig, i) in aksConfigurations: {
  name: aksDeployments[i].outputs.clusterName
  id: aksDeployments[i].outputs.clusterId
  fqdn: aksDeployments[i].outputs.clusterFqdn
  kubeletIdentity: aksDeployments[i].outputs.kubeletIdentityObjectId
  keyVaultSecrets: keyVaultSecrets
}]
