Function Get-SpotInstanceCost {

    <#
    .SYNOPSIS
        This function will retrieve the Spot Instance cost for the specified region and SKU type.
    #>

    param (
        [Parameter()]
        [string]
        $RegionName,
    
        [Parameter()]
        [string]
        $SkuType,
    
        [Parameter()]
        [string]
        $SubscriptionId
    )

    $table  = @()
    $params = @{

        'Method'             = "Get"
        'Uri'                = "https://prices.azure.com/api/retail/prices?`$filter=armRegionName eq '$($regionName)' and armSkuName eq '$($SkuType)' and priceType eq 'Consumption' and contains(meterName, 'Spot')"
        'Headers'            = @{ "Content-Type" = "application/json" }

    }
    
    try {

        $getSpotPrice = Invoke-RestMethod @params
    
        if ($getSpotPrice.Items.Count -gt 0) {

            $spotPrices  = $getSpotPrice.Items

            ForEach($row in $spotPrices) {

                $obj = [PSCustomObject]@{

                    productName        = $row.productName
                    sku                = $row.armSkuName
                    serviceFamily      = $row.serviceFamily
                    currencyCode       = $row.currencyCode
                    retailPrice        = $row.armRegionName
                    unitPrice          = $row.unitPrice.ToString("N5")
                    montlyPrice        = ($row.unitPrice * 730).toString("N5")
                    effectiveStartDate = $row.effectiveStartDate

                }

                $table += $obj

            }

            return $table | Format-Table -AutoSize

        }
        else {

            Write-Output "[Error] - Unable to retrieve the Spot Price for the VM SKU: $SkuType"
            return

        }

    }
    catch {

        Write-Output "[Error] - $($_.Exception.Message)"
        return

    }

}

Get-SpotInstanceCost -RegionName "uksouth" -SkuType "Standard_F1s"