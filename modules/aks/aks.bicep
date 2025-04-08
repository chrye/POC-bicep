// filepath: c:\demo-ghcopilot\modules\aks\aks.bicep
@description('Name of the AKS cluster')
param clusterName string

@description('Location for the AKS cluster')
param location string = resourceGroup().location

@description('Kubernetes version')
param kubernetesVersion string = '1.28.3'

@description('Tags to apply to the AKS cluster')
param tags object = {}

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
  acrId: ''
}

@description('Key vault configuration for secrets')
param keyVaultConfiguration object = {
  keyVaultName: ''
  keyVaultResourceGroupName: resourceGroup().name
  secrets: []  // Array of {name, value} objects
}

@description('Pod CIDR')
param podCidr string = '10.244.0.0/16'

@description('Service CIDR')
param serviceCidr string = '10.0.0.0/16'

@description('DNS Service IP')
param dnsServiceIP string = '10.0.0.10'

@description('Docker Bridge CIDR')
param dockerBridgeCidr string = '172.17.0.1/16'

@description('System node pool configuration')
param systemNodePool object = {
  name: 'system'
  count: 3
  vmSize: 'Standard_D4s_v3'
  osDiskSizeGB: 128
  osDiskType: 'Managed'
  maxPods: 30
  minCount: 3
  maxCount: 5
  enableAutoScaling: true
  mode: 'System'
  availabilityZones: ['1', '2', '3']
}

@description('User node pools configuration')
param userNodePools array = []

@description('Enable Workload Identity feature')
param enableWorkloadIdentity bool = true

@description('AKS addon profiles')
param addonProfiles object = {
  azurePolicy: {
    enabled: true
  }
  azureKeyvaultSecretsProvider: {
    enabled: true
    config: {
      enableSecretRotation: 'true'
      rotationPollInterval: '2m'
    }
  }
}

@description('Managed identities configuration')
param managedIdentitiesConfig object = {
  createIdentities: true
  clusterIdentity: {
    name: ''
    resourceGroupName: resourceGroup().name
  }
}

// Reference existing VNet if specified
resource existingVnet 'Microsoft.Network/virtualNetworks@2023-04-01' existing = if (!empty(vnetConfiguration.vnetName)) {
  name: vnetConfiguration.vnetName
  scope: resourceGroup(vnetConfiguration.vnetResourceGroupName)
}

// Reference existing subnet if VNet is specified
resource existingSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-04-01' existing = if (!empty(vnetConfiguration.vnetName) && !empty(vnetConfiguration.subnetName)) {
  parent: existingVnet
  name: vnetConfiguration.subnetName
}

// Reference or create cluster identity
resource clusterIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: !empty(managedIdentitiesConfig.clusterIdentity.name) ? managedIdentitiesConfig.clusterIdentity.name : '${clusterName}-identity'
  scope: resourceGroup(managedIdentitiesConfig.clusterIdentity.resourceGroupName)
}

// Process the secrets passed from Key Vault
var secretProviderClass = !empty(keyVaultConfiguration.secrets) ? {
  enabled: true
  secretProviderClassConfig: {
    name: '${clusterName}-secrets-provider-class'
    keyvaultName: keyVaultConfiguration.keyVaultName
    tenantId: subscription().tenantId
    secrets: [for secret in keyVaultConfiguration.secrets: {
      secretName: secret.name
      secretAlias: secret.name
    }]
  }
} : {}

// Create AKS cluster
resource aksCluster 'Microsoft.ContainerService/managedClusters@2023-07-01' = {
  name: clusterName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${clusterIdentity.id}': {}
    }
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: '${clusterName}-dns'
    enableRBAC: true
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      podCidr: podCidr
      serviceCidr: serviceCidr
      dnsServiceIP: dnsServiceIP
      dockerBridgeCidr: dockerBridgeCidr
      outboundType: 'loadBalancer'
    }
    agentPoolProfiles: concat([
      {
        name: systemNodePool.name
        count: systemNodePool.count
        vmSize: systemNodePool.vmSize
        osDiskSizeGB: systemNodePool.osDiskSizeGB
        osDiskType: systemNodePool.osDiskType
        maxPods: systemNodePool.maxPods
        minCount: systemNodePool.?minCount
        maxCount: systemNodePool.?maxCount
        enableAutoScaling: systemNodePool.enableAutoScaling
        availabilityZones: systemNodePool.?availabilityZones
        mode: systemNodePool.?mode ?? 'System'
        vnetSubnetID: !empty(vnetConfiguration.vnetName) && !empty(vnetConfiguration.subnetName) ? existingSubnet.id : null
        type: 'VirtualMachineScaleSets'
        osType: 'Linux'
      }
    ], [for userPool in userNodePools: {
      name: userPool.name
      count: userPool.count
      vmSize: userPool.vmSize
      osDiskSizeGB: userPool.osDiskSizeGB
      osDiskType: userPool.osDiskType
      maxPods: userPool.maxPods
      minCount: userPool.?minCount
      maxCount: userPool.?maxCount
      enableAutoScaling: userPool.enableAutoScaling
      availabilityZones: userPool.?availabilityZones
      mode: 'User'
      vnetSubnetID: !empty(vnetConfiguration.vnetName) && !empty(vnetConfiguration.subnetName) ? existingSubnet.id : null
      type: 'VirtualMachineScaleSets'
      osType: 'Linux'
    }])
    addonProfiles: union(addonProfiles, !empty(secretProviderClass) ? {
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '2m'
        }
      }
    } : {})
    securityProfile: {
      workloadIdentity: {
        enabled: enableWorkloadIdentity
      }
    }
  }
}

// Output the AKS cluster details
output clusterName string = aksCluster.name
output clusterId string = aksCluster.id
output clusterFqdn string = aksCluster.properties.fqdn
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId

// Conditionally output secret provider class info if secrets are provided
output secretsProvided bool = !empty(keyVaultConfiguration.secrets)
output secretProviderClassName string = !empty(secretProviderClass) ? secretProviderClass.secretProviderClassConfig.name : ''
