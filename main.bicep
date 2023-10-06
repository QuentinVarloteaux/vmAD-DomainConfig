@description('Nom du client, sert a definir le nom des VMs')
param nomClient string

@description('Recupere la localisation du groupe de ressource')
param location string = resourceGroup().location

@description('concatene le nom du client et le suffixe du nom de la VM')
param vmAdName string = concat(nomClient,'-AD')

@description('Version de l OS de la machine virtuelle')
@allowed([
  '2022-datacenter-g2'
  '2022-datacenter-azure-edition'
  '2019-Datacenter'
])
param osVersion string = '2022-datacenter-azure-edition'

@description('Taille de la machine virtuelle')
@allowed([
  'Standard_B1ms'
  'Standard_B2s'
  'Standard_B2ms'
  'Standard_D2s_v3'
  'Standard_D4s_v3'
])
param vmSize string

@description('Nom de l administrateur de la machine virtuelle')
param adminUsername string

@description('Mot de passe de l administrateur de la machine virtuelle')
@secure()
param adminPassword string

@description('Adresse ip locale de la VM AD')
param vmAdIPLocal string = '10.0.0.4'

@description('Nom de l addresse IP Publique de la VM')
param publicIpName string = concat(vmAdName,'-IP')


@description('Type d allocation de l adresse IP Publique de la VM')
@allowed([
  'Dynamic'
  'Static'
])
param publicIpAllocationmethod string = 'Dynamic' 

@description('SKU de l ip publique de la VM')
@allowed([
  'Basic'
  'Standard'
])
param publicIpSku string = 'Basic'

@description('Type de securite de la VM')
@allowed([
  'Standard'
  'TrustedLaunch'
])
param securityType string = 'TrustedLaunch'

@description('Nom DNS unique pour l ip publique de la VM')
param dnsLabelPrefix string = toLower('${vmAdName}-${uniqueString(resourceGroup().id, vmAdName)}')

@description('Nom de la foret AD')
param domainName string

@description('The location of resources, such as templates and DSC modules, that the template depends on')
param _artifactsLocation string = deployment().properties.templateLink.uri

@description('Auto-generated token to access _artifactsLocation. Leave it blank unless you need to provide your own value.')
@secure()
param _artifactsLocationSasToken string = ''

@description('The DNS prefix for the public IP address used by the Load Balancer')
param dnsPrefix string

var storageAccountName = 'bootdiags${uniqueString(resourceGroup().id)}'
var nicName = concat('nic-${vmAdName}')
var virtualNetworkName = concat('VNET-',nomClient,'-${location}')
var subnetName = concat('snet-${nomClient}-${location}')
var nsgName = 'default-NSG'
var addressPrefix = '10.0.0.0/16'
var subnetPrefix = '10.0.0.0/24'
var extensionName = 'GuestAttestation'
var extensionPublisher = 'Microsoft.Azure.Security.WindowsAttestation'
var extensionVersion = '1.0'
var maaTenantName = 'GuestAttestation'
var maaEndpoint = substring('emptyStrung', 0, 0)
var securityProfileJson = {
  uefiSettings : {
    secureBootEnabled: true
    vTpmEnabled: true
  }
  securityType: securityType
}


resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: publicIpName
  location: location
  sku: {
    name: publicIpSku
  }
  properties: {
    publicIPAllocationMethod: publicIpAllocationmethod
    dnsSettings: {
      domainNameLabel: dnsLabelPrefix
    }
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'default-allow-3389'
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '3389'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetPrefix
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
        }
      }
    ]
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: vmAdIPLocal
          publicIPAddress: {
            id: publicIp.id
          }
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, subnetName)
          }
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}

resource VMAD 'Microsoft.Compute/virtualMachines@2023-07-01' = {
  name: vmAdName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      adminUsername: adminUsername
      adminPassword: adminPassword
      computerName: vmAdName
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: osVersion
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: storageAccount.properties.primaryEndpoints.blob
      }
    }
    securityProfile: ((securityType == 'TrustedLaunch') ? securityProfileJson : null)
  }
}

resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2023-07-01' = if ((securityType == 'TrsutedLaunch') && ((securityProfileJson.uefiSettings.secureBootEnabled == true) && (securityProfileJson.uefiSettings.vTpmEnabled == true))) {
  parent: VMAD
  name: extensionName
  location: location
  properties: {
    publisher: extensionPublisher
    type: extensionName
    typeHandlerVersion: extensionVersion
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    settings: {
      AttestationConfig: {
        MaaSettings: {
          maaEndpoint: maaEndpoint
          maaTenantName: maaTenantName
        }
      }
    }
  }
}

resource createADForest 'Microsoft.Compute/virtualMachines/extensions@2023-07-01' = {
  parent: VMAD
  name: 'CreateADForest'
  location: location
  properties: {
    publisher: 'Microsoft.Powershell'
    type: 'DSC'
    typeHandlerVersion: '2.19'
    autoUpgradeMinorVersion: true
    settings: {
      ModulesUrl: uri(_artifactsLocation, 'DSC/CreateADPDC.zip${_artifactsLocationSasToken}')
      ConfigurationFunction: 'CreateADPDC.ps1\\CreateADPDC'
      Properties: {
        DomainName: domainName
        AdminCreds: {
          UserName: adminUsername
          Password: 'PrivateSettingsRef:AdminPassword'
        }
      }
    }
    protectedSettings: {
      Items: {
        AdminPassword: adminPassword
      }
    }
  }
}

output hostname string = publicIp.properties.dnsSettings.fqdn
output adminPW string = adminPassword
