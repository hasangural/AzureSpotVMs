$environmentConfig = [ordered]@{
    "resourceGroup"  = @{

        type     = "ResourceGroup"
        name     = "rg-"
        location = "uksouth"

    }

    "virtualNetwork" = @{

        type          = "VirtualNetwork"
        Name          = "vnt-"
        AddressPrefix = "10.10.10.0/24"
        Subnets       = @{

            "AzureBastionSubnet" = @{ AddressPrefix = "10.10.10.0/27" }
            "subnet-0001"        = @{ AddressPrefix = "10.10.10.32/27" }
            "subnet-0002"        = @{ AddressPrefix = "10.10.10.64/27" }
        }
        deployBastion = $true 
    }

    "virtualMachines" = @{

        "type"              = "VirtualMachine"
        "vmNamePrefix"      = "vm-" # This will be used to create the VM name
        "Size"              = "Standard_F1s"
        "vmCount"           = 4
        "MaxPrice"          = -1
        "Image"             = "Canonical:UbuntuServer:18.04-LTS:latest"
        "SubnetName"        = "subnet-0001"
        "UserName"          = "btadmin"
        "Password"          = "AVNMLab123!"

    }
}


Function New-AzSpotVMs {
  <#
    .SYNOPSIS
        The function will create the Azure VMs using the Spot Instance pricing.
        Author: Hasan Gural - Azure VMP
        Version: BETA
    .DESCRIPTION
        Demo function to create the Azure VMs using the Spot Instance pricing.
    .EXAMPLE
        If you set the max price to be -1, the VM won't be evicted based on price.
        Function will support multiple VMs and Bastion Hosts.
    #>
    
    [CmdletBinding()]
    param (
        [Parameter()]
        [PSCustomObject]
        $environmentConfig,
    
        [Parameter()]
        [string]
        $envNamePrefix,
    
        [Parameter()]
        [string]
        $SubscriptionId
    )

    $WarningPreference = "SilentlyContinue"
    
    ForEach ($item in $environmentConfig.Keys) {

        if ($environmentConfig.$item.type -eq "ResourceGroup") {

            $rgDef = @{

                Name              = $environmentConfig.$item.name + $envNamePrefix    # Name of the resource group                                   
                Location          = $environmentConfig.$item.location                 # location of the resource group

            }

            Write-Output "[+] - Creating Resource Group: $($rgDef.Name)"
            Write-Output "[+] - Resource Group location: $($rgDef.Location)"

            New-AzResourceGroup @rgDef -Force -Confirm:$false | Out-Null

        }
        elseif ($environmentConfig.$item.type -eq "VirtualNetwork") {
    
            $vNetDef = @{
    
                Name              = $environmentConfig.$item.Name + $envNamePrefix    # Name of the virtual network from the network map                                      
                AddressPrefix     = $environmentConfig.$item.AddressPrefix            # Address prefix for the virtual network.
                ResourceGroupName = $rgDef.Name                                       # Resource group name
                Location          = "uksouth"                                         # Location of the virtual network
        
                Subnet            = ForEach ($subnet in $environmentConfig.$item.Subnets.Keys) {
        
                    Write-Information "Creating subnet configuration for subnet '$subnet', in network '$item'" 
                    New-AzVirtualNetworkSubnetConfig -Name $subnet -AddressPrefix $environmentConfig.$item.Subnets.$subnet.AddressPrefix
                }
            }
    
            $validateRGexists = Get-AzResourceGroup -Name $rgDef.Name -ErrorAction SilentlyContinue

            if ($null -ne $validateRGexists) {

                Write-Output "[+] - Waiting Resource Group: $($rgDef.Name) to be created"
                Write-Output "[+] - Resource Group location: $($rgDef.Location)"

                Start-Sleep -Seconds 5

            }

            Write-Output "[+] - Creating Virtual Network: $($vNetDef.Name)"
            Write-Output "[+] - Virtual Network adress space: $($vNetDef.AddressPrefix)"
            Write-Output "[+] - Virtual Network subnets: $($vNetDef.Subnet.name)"

            New-AzVirtualNetwork @vNetDef -Force -Confirm:$false  | Out-Null
    
            Write-Output "[+] - Virtual Network has been created: $item"
    
            if ($environmentConfig.$item.deployBastion -eq $true) {
    
                Write-Output "[+] - Creating Bastion Host: bst-$envNamePrefix"
    
                #Make sure the Bastion Host IP is available
                $createPIP = New-AzPublicIpAddress -Name "bst-$envNamePrefix-pip" -ResourceGroupName $rgDef.Name `
                                                   -Location "uksouth" -AllocationMethod Static -Sku Standard -Force
    
                $bastionDef = @{
    
                    Name                 = ("bst-" + $envNamePrefix)
                    ResourceGroupName    = $rgDef.Name
                    VirtualNetworkName   = $vNetDef.Name
                    VirtualNetworkRgName = $rgDef.Name
                    PublicIpAddressId    = $createPIP.Id
                    ScaleUnit            = 2
                    Sku                  = "Standard"
    
                }
    
                New-AzBastion @bastionDef -Asjob | Out-Null
    
                Write-Output "[+] - Bastion Host is on the way: bastion-$envNamePrefix - Please wait for it to be created: bst-$envNamePrefix"
    
                #Region Bastion Feature - This is a workaround for the fact that the Bastion Host is not yet available in the Azure PowerShell module.
                # Intention of this is to enable the shareable link feature for the Bastion Host. We will hit the REST API directly
    
                Start-Job -ArgumentList $envNamePrefix, $rgDef, $vNetDef, $subscriptionId -ScriptBlock {
    
                    [CmdletBinding()]
                    param (
                        [Parameter()]
                        $envNamePrefix,
    
                        [Parameter()]
                        $rgDef,

                        [Parameter()]
                        $vNetDef,
    
                        [Parameter()]
                        $subscriptionId
                    )
    
                    while ($true) {
    
                        $bastionStatus = Get-AzBastion -Name "bst-$envNamePrefix" -ResourceGroupName $rgDef.Name -ErrorAction SilentlyContinue
    
                        if ($bastionStatus.ProvisioningState -eq "Succeeded") {
    
                            $header = @{
    
                                "Content-Type" = "application/json"
                                Authorization  = ("Bearer " + (Get-AzAccessToken).Token)
                            }
            
                            $requestBody = @{
    
                                location   = $($rgDef.Location)
                                properties = @{
                                    enableShareableLink = $true
                                    ipconfigurations    = @(
                                        @{
                                            name       = "IpConf"
                                            properties = @{
                                                publicIPAddress = @{
                                                    id = "/subscriptions/$($subscriptionId)/resourceGroups/$($rgDef.Name)/providers/Microsoft.Network/publicIPAddresses/bastion-$($envNamePrefix)-pip"
                                                }
                                                subnet          = @{
                                                    id = "/subscriptions/$($subscriptionId)/resourceGroups/$($rgDef.Name)/providers/Microsoft.Network/virtualNetworks/$($vNetDef.Name)/subnets/AzureBastionSubnet"
                                                }
                                            }
                                        }
                                    )
                                }
                            }
            
                            $uri = "https://management.azure.com/subscriptions/$($subscriptionId)/resourceGroups/$($rgDef.Name)/providers/Microsoft.Network/bastionHosts/bastion-vnt-0001?api-version=2022-07-01"
            
                            Invoke-RestMethod -Method Put -Uri $uri -Headers $header -Body (ConvertTo-Json $requestBody -Depth 10) | Out-Null
                        }
                        else {
    
                            Write-Output "Bastion Host is not ready yet. Waiting 30 seconds before checking again"
                            Start-Sleep -Seconds 30
                        }
                    }
            
                } | Out-Null
    
                #End Bastion Feature
            }
        }
        elseif ($environmentConfig.$item.type -eq "VirtualMachine") {

            For ($vm = 1; $vm -le $environmentConfig.$item.vmCount; $vm++) {

                $vmNumber = '{0:d2}' -f $vm
                
                $vmProps = @{
        
                    Name               = ("vm-$($vmNumber)-" + $envNamePrefix)
                    ResourceGroupName  = $rgDef.Name
                    Location           = $rgDef.Location
                    VirtualNetworkName = $vNetDef.Name
                    SubnetName         = $environmentConfig.$item.SubnetName
                    Size               = $environmentConfig.$item.Size
                    Image              = $environmentConfig.$item.Image
                    SecurityGroupName  = ("nsg-" + $envNamePrefix)
                    Priority           = "Spot"
                    MaxPrice           = $environmentConfig.$item.MaxPrice
                    EvictionPolicy     = "Deallocate"
                    OpenPorts          = @("3389")
                    Credential         = New-Object System.Management.Automation.PSCredential($environmentConfig.$item.UserName, (ConvertTo-SecureString -String $environmentConfig.$item.Password -AsPlainText -Force))
                }

                Write-Output "[+] - Creating Virtual Machine: $($vmProps.Name)"
        
                New-AzVM @vmProps -AsJob | Out-Null
        
                Write-Output "[+] - Virtual Machine is on the way: $($vmProps.Name) - Please wait for the VM to be created."

            }
    
        }

    }

}


New-AzSpotVMs -environmentConfig $environmentConfig -envNamePrefix "lab10" -SubscriptionId "3d2f2633-7e51-4875-97ed-132ac14de75b"
