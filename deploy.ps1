param (
    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'int', 'load', 'npd', 'prd')]
    [string]$Environment,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$Location = 'eastus2',
    
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId = '',
    
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf,

    [Parameter(Mandatory = $false)]
    [ValidateSet('acr', 'aks', 'frontdoor', 'all', 'unified')]
    [string]$DeploymentType = 'unified'
)

# Set error action preference
$ErrorActionPreference = 'Stop'

# Get the current directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# Define path variables
$bicepFolder = Join-Path $scriptPath "bicep"
$environmentFolder = Join-Path $scriptPath "environments\$Environment"

Write-Host "Starting deployment for $Environment environment" -ForegroundColor Green

# Connect to Azure if SubscriptionId is provided
if ($SubscriptionId) {
    Write-Host "Connecting to subscription: $SubscriptionId" -ForegroundColor Yellow
    az account set --subscription $SubscriptionId
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to set subscription. Please make sure you're logged in and the subscription ID is correct."
        exit 1
    }
}

# Check if the resource group exists, create it if it doesn't
$rgExists = az group show --name $ResourceGroupName 2>$null
if (-not $rgExists) {
    Write-Host "Resource group $ResourceGroupName doesn't exist. Creating it..." -ForegroundColor Yellow
    az group create --name $ResourceGroupName --location $Location
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create resource group $ResourceGroupName."
        exit 1
    }
}

# Unified deployment (VNet + ACR + AKS + Front Door)
if ($DeploymentType -eq 'unified') {
    $mainParameterFile = Join-Path $environmentFolder "main.parameters.json"
    $mainBicepFile = Join-Path $bicepFolder "main.bicep"

    if (Test-Path $mainParameterFile) {
        Write-Host "Deploying unified infrastructure from $mainBicepFile with parameters from $mainParameterFile" -ForegroundColor Yellow
        
        $deploymentName = "unified-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        
        $deployCommand = "az deployment group create --name $deploymentName --resource-group $ResourceGroupName --template-file $mainBicepFile --parameters @$mainParameterFile"
        
        if ($WhatIf) {
            $deployCommand += " --what-if"
        }
        
        Write-Host "Executing: $deployCommand" -ForegroundColor Cyan
        Invoke-Expression $deployCommand
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Unified deployment failed."
            exit 1
        }
    } else {
        Write-Warning "Main parameter file not found: $mainParameterFile"
    }
}

# Deploy Front Door resources if specified
elseif ($DeploymentType -eq 'frontdoor') {
    $frontDoorParameterFile = Join-Path $environmentFolder "frontdoor.parameters.json"
    $frontDoorBicepFile = Join-Path $bicepFolder "main-frontdoor.bicep"

    if (Test-Path $frontDoorParameterFile) {
        Write-Host "Deploying Front Door resources from $frontDoorBicepFile with parameters from $frontDoorParameterFile" -ForegroundColor Yellow
        
        $deploymentName = "frontdoor-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        
        $deployCommand = "az deployment group create --name $deploymentName --resource-group $ResourceGroupName --template-file $frontDoorBicepFile --parameters @$frontDoorParameterFile"
        
        if ($WhatIf) {
            $deployCommand += " --what-if"
        }
        
        Write-Host "Executing: $deployCommand" -ForegroundColor Cyan
        Invoke-Expression $deployCommand
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Front Door deployment failed."
            exit 1
        }
    } else {
        Write-Warning "Front Door parameter file not found: $frontDoorParameterFile"
    }
}

# Deploy ACR resources if specified
elseif ($DeploymentType -eq 'acr' -or $DeploymentType -eq 'all') {
    $acrParameterFile = Join-Path $environmentFolder "acr.parameters.json"
    $acrBicepFile = Join-Path $bicepFolder "main-acr.bicep"

    if (Test-Path $acrParameterFile) {
        Write-Host "Deploying ACR resources from $acrBicepFile with parameters from $acrParameterFile" -ForegroundColor Yellow
        
        $deploymentName = "acr-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        
        $deployCommand = "az deployment group create --name $deploymentName --resource-group $ResourceGroupName --template-file $acrBicepFile --parameters @$acrParameterFile"
        
        if ($WhatIf) {
            $deployCommand += " --what-if"
        }
        
        Write-Host "Executing: $deployCommand" -ForegroundColor Cyan
        Invoke-Expression $deployCommand
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error "ACR deployment failed."
            exit 1
        }
    } else {
        Write-Warning "ACR parameter file not found: $acrParameterFile"
    }

    # Deploy AKS resources if "all" is specified
    if ($DeploymentType -eq 'all') {
        $aksParameterFile = Join-Path $environmentFolder "aks.parameters.json"
        $aksBicepFile = Join-Path $bicepFolder "main-aks.bicep"

        if (Test-Path $aksParameterFile) {
            Write-Host "Deploying AKS resources from $aksBicepFile with parameters from $aksParameterFile" -ForegroundColor Yellow
            
            $deploymentName = "aks-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            
            $deployCommand = "az deployment group create --name $deploymentName --resource-group $ResourceGroupName --template-file $aksBicepFile --parameters @$aksParameterFile"
            
            if ($WhatIf) {
                $deployCommand += " --what-if"
            }
            
            Write-Host "Executing: $deployCommand" -ForegroundColor Cyan
            Invoke-Expression $deployCommand
            
            if ($LASTEXITCODE -ne 0) {
                Write-Error "AKS deployment failed."
                exit 1
            }
        } else {
            Write-Warning "AKS parameter file not found: $aksParameterFile"
        }
        
        # Deploy Front Door resources if "all" is specified
        $frontDoorParameterFile = Join-Path $environmentFolder "frontdoor.parameters.json"
        $frontDoorBicepFile = Join-Path $bicepFolder "main-frontdoor.bicep"

        if (Test-Path $frontDoorParameterFile) {
            Write-Host "Deploying Front Door resources from $frontDoorBicepFile with parameters from $frontDoorParameterFile" -ForegroundColor Yellow
            
            $deploymentName = "frontdoor-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            
            $deployCommand = "az deployment group create --name $deploymentName --resource-group $ResourceGroupName --template-file $frontDoorBicepFile --parameters @$frontDoorParameterFile"
            
            if ($WhatIf) {
                $deployCommand += " --what-if"
            }
            
            Write-Host "Executing: $deployCommand" -ForegroundColor Cyan
            Invoke-Expression $deployCommand
            
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Front Door deployment failed."
                exit 1
            }
        } else {
            Write-Warning "Front Door parameter file not found: $frontDoorParameterFile"
        }
    }
}

# Deploy only AKS resources if specified
elseif ($DeploymentType -eq 'aks') {
    $aksParameterFile = Join-Path $environmentFolder "aks.parameters.json"
    $aksBicepFile = Join-Path $bicepFolder "main-aks.bicep"

    if (Test-Path $aksParameterFile) {
        Write-Host "Deploying AKS resources from $aksBicepFile with parameters from $aksParameterFile" -ForegroundColor Yellow
        
        $deploymentName = "aks-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        
        $deployCommand = "az deployment group create --name $deploymentName --resource-group $ResourceGroupName --template-file $aksBicepFile --parameters @$aksParameterFile"
        
        if ($WhatIf) {
            $deployCommand += " --what-if"
        }
        
        Write-Host "Executing: $deployCommand" -ForegroundColor Cyan
        Invoke-Expression $deployCommand
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error "AKS deployment failed."
            exit 1
        }
    } else {
        Write-Warning "AKS parameter file not found: $aksParameterFile"
    }
}

Write-Host "Deployment completed successfully!" -ForegroundColor Green