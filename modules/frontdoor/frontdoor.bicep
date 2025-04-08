// filepath: c:\demo-ghcopilot\modules\frontdoor\frontdoor.bicep
@description('Name of the Front Door profile')
param profileName string

@description('SKU name for Front Door')
@allowed([
  'Standard_AzureFrontDoor'
  'Premium_AzureFrontDoor'
])
param skuName string = 'Premium_AzureFrontDoor'

@description('Location for the Front Door profile')
param location string = 'global'

@description('Origin group configuration')
param originGroups array = []

@description('Endpoint configuration')
param endpoints array = []

@description('Routes configuration')
param routes array = []

@description('Custom domain configuration with Key Vault certificate')
param customDomains array = []

@description('Key Vault configuration')
param keyVaultConfig object = {
  keyVaultName: ''
  keyVaultResourceGroupName: resourceGroup().name
  certificateNames: []
  keyVaultUri: ''
}

@description('Tags for the resource')
param tags object = {}

// Create reference to existing key vault if specified
resource existingKeyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = if(!empty(keyVaultConfig.keyVaultName)) {
  name: keyVaultConfig.keyVaultName
  scope: resourceGroup(keyVaultConfig.keyVaultResourceGroupName)
}

// Define Front Door user-assigned managed identity for Key Vault access
resource frontDoorManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${profileName}-fd-identity'
  location: location
  tags: tags
}

// Assign Secret Reader role to Front Door managed identity on Key Vault
resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if(!empty(keyVaultConfig.keyVaultName)) {
  name: guid(existingKeyVault.id, frontDoorManagedIdentity.id, 'KeyVaultSecretsUser')
  scope: existingKeyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User role
    principalId: frontDoorManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Create Front Door profile
resource frontDoorProfile 'Microsoft.Cdn/profiles@2023-07-01-preview' = {
  name: profileName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    originResponseTimeoutSeconds: 60
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${frontDoorManagedIdentity.id}': {}
    }
  }
}

// Create origin groups
resource originGroup 'Microsoft.Cdn/profiles/originGroups@2023-07-01-preview' = [for (group, index) in originGroups: {
  name: group.name
  parent: frontDoorProfile
  properties: {
    loadBalancingSettings: {
      sampleSize: group.?loadBalancingSettings?.sampleSize ?? 4
      successfulSamplesRequired: group.?loadBalancingSettings?.successfulSamplesRequired ?? 3
      additionalLatencyInMilliseconds: group.?loadBalancingSettings?.additionalLatencyInMilliseconds ?? 50
    }
    healthProbeSettings: {
      probePath: group.?healthProbeSettings?.probePath ?? '/'
      probeRequestType: group.?healthProbeSettings?.probeRequestType ?? 'HEAD'
      probeProtocol: group.?healthProbeSettings?.probeProtocol ?? 'Http'
      probeIntervalInSeconds: group.?healthProbeSettings?.probeIntervalInSeconds ?? 100
    }
    sessionAffinityState: group.?sessionAffinityState ?? 'Disabled'
  }
}]

// Create origins within each origin group
resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2023-07-01-preview' = [for (org, i) in flatten([for (group, groupIndex) in originGroups: [for (origin, originIndex) in group.origins: {
  groupName: group.name
  groupIndex: groupIndex
  name: origin.name
  hostName: origin.hostName
  hostHeader: origin.?hostHeader ?? origin.hostName
  httpPort: origin.?httpPort ?? 80
  httpsPort: origin.?httpsPort ?? 443
  priority: origin.?priority ?? 1
  weight: origin.?weight ?? 1000
  enabled: origin.?enabled ?? true
  enabledState: origin.?enabledState ?? 'Enabled'
  enforceCertificateNameCheck: origin.?enforceCertificateNameCheck ?? true
  originIndex: originIndex
}]]): {
  name: org.name
  parent: originGroup[org.groupIndex]
  properties: {
    hostName: org.hostName
    httpPort: org.httpPort
    httpsPort: org.httpsPort
    originHostHeader: org.hostHeader
    priority: org.priority
    weight: org.weight
    enabledState: org.enabledState
    enforceCertificateNameCheck: org.enforceCertificateNameCheck
  }
}]

// Create custom domains with Key Vault certificate integration
resource customDomain 'Microsoft.Cdn/profiles/customDomains@2023-07-01-preview' = [for (domain, i) in customDomains: {
  name: replace(domain.hostName, '.', '-')
  parent: frontDoorProfile
  properties: {
    hostName: domain.hostName
    tlsSettings: {
      certificateType: 'CustomerCertificate'
      minimumTlsVersion: domain.?minimumTlsVersion ?? 'TLS12'
      secret: {
        id: domain.?certificateId ?? (!empty(keyVaultConfig.keyVaultName) && !empty(domain.?certificateName) 
          ? '${existingKeyVault.properties.vaultUri}secrets/${domain.certificateName}'
          : '')
        // For Premium SKU with Key Vault integration
        source: !empty(keyVaultConfig.keyVaultName) ? 'AzureKeyVault' : null
      }
    }
  }
  dependsOn: [
    keyVaultRoleAssignment // Wait for role assignment to complete before accessing certificates
  ]
}]

// Create endpoints
resource endpointResource 'Microsoft.Cdn/profiles/afdEndpoints@2023-07-01-preview' = [for (endpoint, i) in endpoints: {
  name: endpoint.name
  parent: frontDoorProfile
  location: location
  properties: {
    enabledState: endpoint.?enabledState ?? 'Enabled'
  }
}]

// Create routes for each endpoint
resource routeResource 'Microsoft.Cdn/profiles/afdEndpoints/routes@2023-07-01-preview' = [for (route, i) in routes: {
  name: route.name
  parent: endpointResource[route.endpointIndex]
  properties: {
    originGroup: {
      id: originGroup[route.originGroupIndex].id
    }
    supportedProtocols: route.?supportedProtocols ?? ['Http', 'Https']
    patternsToMatch: route.?patternsToMatch ?? ['/*']
    forwardingProtocol: route.?forwardingProtocol ?? 'MatchRequest'
    linkToDefaultDomain: route.?linkToDefaultDomain ?? 'Enabled'
    httpsRedirect: route.?httpsRedirect ?? 'Enabled'
    enabledState: route.?enabledState ?? 'Enabled'
    // Add custom domain if specified
    customDomains: contains(route, 'customDomainIndex') ? [
      {
        id: customDomain[route.customDomainIndex].id
      }
    ] : []
  }
  dependsOn: [
    customDomain // Ensure custom domains are created first
  ]
}]

@description('Front Door Profile ID')
output profileId string = frontDoorProfile.id

@description('Front Door Profile Name')
output profileName string = frontDoorProfile.name

@description('Front Door Endpoints')
output endpoints array = [for (endpoint, i) in endpoints: {
  name: endpoint.name
  hostName: '${endpoint.name}.${reference(frontDoorProfile.id, '2023-07-01-preview').frontDoorId}.azurefd.net'
}]

@description('Custom Domain Details')
output customDomains array = [for (domain, i) in customDomains: {
  name: replace(domain.hostName, '.', '-')
  hostName: domain.hostName
}]
