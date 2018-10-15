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
        Last Updated  :    
        Version       :    1.0

    .INPUTS
        Parameter CSV file (NSGParameters.csv)
#>

$CSVPath = "D:\Projects\MI\Automation\NSGDeployment\NSGParameters.csv"
$AZCredential = Get-Credential
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
    
    #Logging into the Subscription
    Import-Module AzureRM    
    Login-AzureRmAccount -Credential $AZCredential
    $SubcriptionID = "054fa364-65f4-4a93-8850-344cd1148882"
    Select-AzureRmSubscription -SubscriptionID $SubcriptionID
    
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