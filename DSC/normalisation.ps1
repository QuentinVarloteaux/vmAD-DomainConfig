Configuration Normalisation
{   
    Import-DscResource -ModuleName PSDesiredStateConfiguration, ComputerManagementDsc

    Node localhost
    {
       TimeZone CEST
       {
            IsSingleInstance = 'Yes'
            TimeZone         = 'Central European Standard Time' 
       } 

       IEEnhancedSecurityConfiguration 'DisabledForEveryone'
       {
            Role = 'Users'  
            Enabled = $false
       }

       IEEnhancedSecurityConfiguration 'DisabledForAdmins'
       {
            Role = 'Administrators'  
            Enabled = $false
       }

       PowerPlan SetPlanHighPerformance
       {
            IsSingleInstance = 'Yes'
            Name = 'High performance'
       }

       SystemLocale SystemLocaleFR
       {
            IsSingleInstance = 'Yes'
            SystemLocale = 'fr-FR'
       }
    }
}