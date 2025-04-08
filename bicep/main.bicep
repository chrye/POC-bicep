// filepath: c:\demo-ghcopilot\bicep\main.bicep
@description('Location for all resources')
param location string = resourceGroup().location

@description('Virtual network configuration')
param vnetConfig object

@description('ACR configurations')
param acrConfigurations array = []

@description('AKS configurations')
param aksConfigurations array = []

@description('Front Door configurations')
param frontDoorConfigurations array = []

@description('Key vault details for integration')
param keyVaultConfiguration object = {
  keyVaultName: ''
  keyVaultResourceGroupName: resourceGroup().name
  certificateName: ''
  certificateNames: []
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

@description('Private DNS zone IDs for different services')
param privateDnsZones object = {
  acr: ''
  keyvault: ''
  sql: ''
  blob: ''
  file: ''
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

// Deploy the virtual network with subnets
module vnetDeployment '../modules/networking/vnet.bicep' = {
  name: 'vnet-deployment'
  params: {
    vnetName: vnetConfig.name
    location: location
    addressSpace: vnetConfig.addressSpace
    subnets: vnetConfig.subnets
    tags: union(commonTags, vnetConfig.?tags ?? {})
  }
}

// Map subnet resource paths for different services
var acrSubnetId = vnetConfig.subnets
  | map(subnet => subnet.name == vnetConfig.serviceSubnets.acr ? '${vnetDeployment.outputs.id}/subnets/${subnet.name}' : '')
  | first(id => id != '')

var aksSubnetId = vnetConfig.subnets
  | map(subnet => subnet.name == vnetConfig.serviceSubnets.aks ? '${vnetDeployment.outputs.id}/subnets/${subnet.name}' : '')
  | first(id => id != '')

var privateEndpointsSubnetId = vnetConfig.subnets
  | map(subnet => subnet.name == vnetConfig.serviceSubnets.privateEndpoints ? '${vnetDeployment.outputs.id}/subnets/${subnet.name}' : '')
  | first(id => id != '')

// Deploy ACR resources and connect to the ACR subnet
module acrDeployment '../bicep/main-acr.bicep' = if (!empty(acrConfigurations)) {
  name: 'acr-deployment'
  params: {
    location: location
    acrConfigurations: acrConfigurations
    vnetConfiguration: {
      vnetName: vnetConfig.name
      vnetResourceGroupName: resourceGroup().name
      subnetName: vnetConfig.serviceSubnets.acr
    }
    keyVaultConfiguration: keyVaultConfiguration
    privateDnsZoneId: privateDnsZones.acr
    commonTags: commonTags
  }
  dependsOn: [
    vnetDeployment
  ]
}

// Deploy AKS resources and connect to the AKS subnet
module aksDeployment '../bicep/main-aks.bicep' = if (!empty(aksConfigurations)) {
  name: 'aks-deployment'
  params: {
    location: location
    aksConfigurations: [for aksConfig in aksConfigurations: {
      name: aksConfig.name
      kubernetesVersion: aksConfig.?kubernetesVersion ?? '1.28.3'
      vnetName: vnetConfig.name
      vnetResourceGroupName: resourceGroup().name
      subnetName: vnetConfig.serviceSubnets.aks
      tags: union(commonTags, aksConfig.?tags ?? {})
      systemNodePool: aksConfig.?systemNodePool ?? {}
      userNodePools: aksConfig.?userNodePools ?? []
      enableWorkloadIdentity: aksConfig.?enableWorkloadIdentity ?? true
      addonProfiles: aksConfig.?addonProfiles ?? {}
    }]
    vnetConfiguration: {
      vnetName: vnetConfig.name
      vnetResourceGroupName: resourceGroup().name
      subnetName: vnetConfig.serviceSubnets.aks
    }
    acrConfiguration: !empty(acrConfigurations) ? {
      acrName: acrConfigurations[0].name
      acrResourceGroupName: resourceGroup().name
    } : {}
    keyVaultConfiguration: keyVaultConfiguration
    sqlConfiguration: sqlConfiguration
    storageConfiguration: storageConfiguration
    managedIdentitiesConfig: managedIdentitiesConfig
    commonTags: commonTags
  }
  dependsOn: [
    vnetDeployment
    acrDeployment
  ]
}

// Deploy Front Door with Key Vault certificate integration
module frontDoorDeployment '../bicep/main-frontdoor.bicep' = if (!empty(frontDoorConfigurations)) {
  name: 'frontdoor-deployment'
  params: {
    location: location
    frontDoorConfigurations: frontDoorConfigurations
    keyVaultConfiguration: keyVaultConfiguration
    commonTags: commonTags
  }
}

// Output the deployment results
output vnetId string = vnetDeployment.outputs.id
output vnetName string = vnetDeployment.outputs.name
output vnetSubnets array = vnetDeployment.outputs.subnets

output acrDetails array = !empty(acrConfigurations) ? acrDeployment.outputs.acrDetails : []
output aksDetails array = !empty(aksConfigurations) ? aksDeployment.outputs.aksDetails : []
output frontDoorDetails array = !empty(frontDoorConfigurations) ? frontDoorDeployment.outputs.frontDoorDetails : []
