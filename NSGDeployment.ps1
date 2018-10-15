<#
    .SYNOPSIS
        This script will Deploy the NSGs and their Rules to all the Subnets.
    
    .DESCRIPTION
        This script is used in MI Subscription to check if NSGs exists, deploy them, configure the NSG Rules and assign the Subnet to the NSG.
     
    .NOTES
        File          :    MI-NSG-Deploy.ps1
        Author        :    P V Pramod Reddy
        Company       :    LTI
        Email         :    pramodreddy.p.v@lntinfotech.com
        Created       :    27-08-2018
        Last Updated  :    03-10-2018
        Version       :    1.0

    .INPUTS
        Parameter CSV file (NSGParameters.csv)
#>

Param(

    [Parameter(Mandatory= $true)]  
    [PSCredential]$AzureOrgIdCredential,

    [Parameter(Mandatory= $true)]
    [string]$ParameterFileName = "NSGParameters.csv",

    [Parameter(Mandatory= $true)]
    [string]$SubcriptionID = "bb3d0ed0-bf9b-442d-83d5-3b059843dd52",

)

Get-ChildItem -Path C:\Temp -Include NSGParameters.csv | foreach { $_.Delete()}

#   Logging into the Subscription
$Null = Login-AzureRMAccount -Credential $AzureOrgIdCredential  
$Null = Get-AzureRmSubscription -SubscriptionID $SubcriptionID | Select-AzureRMSubscription

$ContextStorageName = "use2host02mivmstrg001"
$ContextStorageRG = (Get-AzureRmStorageAccount | where {$_.StorageAccountName -eq "$ContextStorageName"}).ResourceGroupName
$ContextStorageKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $ContextStorageRG -Name "$ContextStorageName").key1
$Context = New-AzureStorageContext -StorageAccountName $ContextStorageName -StorageAccountKey $ContextStorageKey
$Null = Get-AzureStorageBlobContent -Context $Context -Blob $ParameterFileName -Container "nsgdeployment-inputs" -Destination 'C:\Temp\' -Force

$CSVPath = Join-Path -Path 'C:\Temp\' -ChildPath $ParameterFileName

try
{
    $ErrorActionPreference = "Stop"
    
    $RuleDetails = Import-Csv "$CSVPath"
    if(!(Test-Path $CSVPath))
    {
        # CSV Path Check
        throw "$CSVPath does not exists"
    }

    $ErrorActionPreference = "Continue"
    
    foreach($Rule in $RuleDetails)
    {
        Write-Output "Working on $($Rule.NSGRuleName), please do not disturb"
        $NSGname=$Rule.networkSecurityGroupName

        # Check and create the NSG
        if((Get-AzureRmNetworkSecurityGroup | Where Name -eq $NSGname) -eq $null)
        {
            $nsg = New-AzureRmNetworkSecurityGroup -Name $Rule.networkSecurityGroupName -ResourceGroupName $Rule.ResourceGroupName -Location $Rule.location
        }
        else
        {
            Write-Output "$($Rule.networkSecurityGroupName) already exists and hence proceeding with creation of NSG Rules"
            $nsg = Get-AzureRmNetworkSecurityGroup -Name $Rule.networkSecurityGroupName -ResourceGroupName $Rule.ResourceGroupName
        }

        # Adding the NSG Security rule.
        $nsg | Add-AzureRmNetworkSecurityRuleConfig -Name $Rule.NSGRuleName -Description $Rule.Description -Access $Rule.Access `
            -Protocol $Rule.Protocol -Direction $Rule.Direction -Priority $Rule.Priority `
            -SourceAddressPrefix $Rule.SourceAddressPrefix.Split(",") -SourcePortRange $Rule.SourcePortRange.Split(",") `
            -DestinationAddressPrefix $Rule.DestinationAddressPrefix.Split(",") -DestinationPortRange $Rule.DestinationPortRange.Split(",")

        # Update the NSG.
        $nsg | Set-AzureRmNetworkSecurityGroup

        # Associate Subnet to NSG
        $VNET = Get-AzureRmVirtualNetwork | where Name -eq $Rule.VNETName
        $Subnet = $VNET.Subnets | where Name -eq $Rule.SubnetName
        $SubnetCIDR = $Subnet.AddressPrefix
        Set-AzureRmVirtualNetworkSubnetConfig -Name $Rule.SubnetName -VirtualNetwork $VNET -AddressPrefix $SubnetCIDR -NetworkSecurityGroup $nsg
        $VNET | Set-AzureRmVirtualNetwork
    }
}
catch
{
    throw $_ 
}