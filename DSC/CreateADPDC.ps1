configuration CreateADPDC 
{ 
    param 
    ( 
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [String]$NomClient,

        [Parameter(Mandatory = $true)]
        [System.String]$Path,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Int]$RetryCount = 20,
        [Int]$RetryIntervalSec = 30
    ) 
    
    Import-DscResource -ModuleName xActiveDirectory, xStorage, xNetworking, PSDesiredStateConfiguration, xPendingReboot
    [System.Management.Automation.PSCredential ]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)
    $Interface = Get-NetAdapter | Where Name -Like "Ethernet*" | Select-Object -First 1
    $InterfaceAlias = $($Interface.Name)

    Node localhost
    {
        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
        }

        WindowsFeature DNS { 
            Ensure = "Present" 
            Name   = "DNS"		
        }

        Script GuestAgent
        {
            SetScript  = {
                Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\WindowsAzureGuestAgent' -Name DependOnService -Type MultiString -Value DNS
                Write-Verbose -Verbose "GuestAgent depends on DNS"
            }
            GetScript  = { @{} }
            TestScript = { $false }
            DependsOn  = "[WindowsFeature]DNS"
        }
        
        Script EnableDNSDiags {
            SetScript  = { 
                Set-DnsServerDiagnostics -All $true
                Write-Verbose -Verbose "Enabling DNS client diagnostics" 
            }
            GetScript  = { @{} }
            TestScript = { $false }
            DependsOn  = "[WindowsFeature]DNS"
        }

        WindowsFeature DnsTools {
            Ensure    = "Present"
            Name      = "RSAT-DNS-Server"
            DependsOn = "[WindowsFeature]DNS"
        }

        xDnsServerAddress DnsServerAddress 
        { 
            Address        = '127.0.0.1' 
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'
            DependsOn      = "[WindowsFeature]DNS"
        }

        xWaitforDisk Disk0
        {
            DiskNumber = 0
            RetryIntervalSec =$RetryIntervalSec
            RetryCount = $RetryCount
        }

        xDisk ADDataDisk {
            DiskNumber  = 0
            DriveLetter = "C"
            DependsOn   = "[xWaitForDisk]Disk0"
        }

        WindowsFeature ADDSInstall { 
            Ensure    = "Present" 
            Name      = "AD-Domain-Services"
            DependsOn = "[WindowsFeature]DNS" 
        } 

        WindowsFeature ADDSTools {
            Ensure    = "Present"
            Name      = "RSAT-ADDS-Tools"
            DependsOn = "[WindowsFeature]ADDSInstall"
        }

        WindowsFeature ADAdminCenter {
            Ensure    = "Present"
            Name      = "RSAT-AD-AdminCenter"
            DependsOn = "[WindowsFeature]ADDSInstall"
        }

        $domainContainer="DC=$($DomainName.Split('.') -join ',DC=')"
         
        xADDomain FirstDS 
        {
            DomainName                    = $DomainName
            DomainAdministratorCredential = $DomainCreds
            SafemodeAdministratorPassword = $DomainCreds
            DatabasePath                  = "C:\Windows\NTDS"
            LogPath                       = "C:\Windows\NTDS"
            SysvolPath                    = "C:\Windows\SYSVOL"
            DependsOn                     = @("[xDisk]ADDataDisk", "[WindowsFeature]ADDSInstall")
        } 

        xWaitForADDomain WaitForDomainInstall
        {
            DomainName           = $DomainName
            DomainUserCredential = $DomainCreds
            RebootRetryCount     = 2
            RetryCount           = 10
            RetryIntervalSec     = 60
            DependsOn            = '[xADDomain]FirstDS'       
        }

        xADOrganizationalUnit CreateAccountOU
        {
            Name                            = $NomClient
            Path                            = $domainContainer
            Ensure                          = 'Present'
            Credential                      = $DomainCreds
            DependsOn                       = '[xWaitForADDomain]WaitForDomainInstall'
        }

        xADUser adminisatech
        {
            Path                          = "OU=$NomClient,$domainContainer"
            DomainName                    = $DomainName
            DomainAdministratorCredential = $domainCred
            UserName                      = 'adminisatech'
            Password                      = $domainCred
            Ensure                        = "Present"
            DependsOn                     = '[xADOrganizationalUnit]CreateAccountOU'

        }

        xADDomainDefaultPasswordPolicy DefaultPasswordPolicy
        {
            DomainName               = $DomainName
            ComplexityEnabled        = $true
            MaxPasswordAge           = 365
            MinPasswordLength        = 8
            PasswordHistoryCount     = 24

        }

    }
} 
