[CmdletBinding()]
param (
    [parameter(mandatory = $false)]$HostpoolName = "hp-fs-peo-va-d-01",
    [parameter(mandatory = $false)]$Environment = "AzureUSGovernment",
    [parameter(mandatory = $false)]$location = 'usgovvirginia'
)

# Connect using a Managed Service Identity
try
{
    $AzureContext = (Connect-AzAccount -Identity -Environment $Environment).context
}
catch
{
    Write-Output "There is no system-assigned user identity. Aborting.";
    exit
}

$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext
# Getting the hostpool first
$hostpool = Get-AzWvdHostPool | Where-Object { $_.Name -eq $hostpoolname }
if ($null -eq $hostpool)
{
    "Hostpool $hostpoolname not found"
    exit;
}
$vms = @()
$hostpoolRg = ($hostpool).id.split("/")[4]

# Select a VM in hostpool
$sessionHosts = Get-AzWvdSessionHost -ResourceGroupName $hostpoolRg -HostPoolName $hostpoolName
foreach($machine in $sessionHosts)
{
    $vm = $machine.name.split('/')[1]
    write-host $Vm
    $vms += $vm
}

# get updated storage account key
$sa = Get-AzStorageAccount -StorageAccountName avdtest -ResourceGroupName NetworkWatcherRG

$rotateDate = Get-AzStorageAccountKey -ResourceGroupName NetworkWatcherRG -Name $sa.StorageAccountName
foreach($saKey in $rotateDate)
{
    if($saKey.CreationTime -lt (Get-date).addHours(-1))
    {
        New-AzStorageAccountKey -ResourceGroupName $sa.ResourceGroupName -Name $sa.StorageAccountName -KeyName $saKey.KeyName -Verbose
    }
}
$key = (Get-AzStorageAccountKey -ResourceGroupName NetworkWatcherRG -Name $sa.StorageAccountName).Value[0]
$endpoint = $sa.PrimaryEndpoints
$primaryEndpoint = ($endpoint.blob.Split("https://$($sa.storageAccountName).blob.")[1]).trim('/')
$accountName = "test"

$fileUris = @("https://raw.githubusercontent.com/mikedzikowski/FSLogixKeyRotationWithRunCommand/main/New-FslogixKeyRotation.ps1")
$Settings = @{"storageAccountName" = $storageAcctName; "storageAccountKey" = $storageKey; "fileUris" = $fileUris; "commandToExecute" = "powershell -ExecutionPolicy Unrestricted -File New-FslogixKeyRotation.ps1"}

#run command to run fslogix script
$vms | ForEach-Object -Parallel {
    $virtualMachine = (Get-AzVM -Name $_)
    Set-AzVMExtension -ResourceGroupName $virtualMachine.ResourceGroupName `
      -Location $virtualMachine.Location `
      -VMName $virtualMachine.Name `
      -Name "fslogix" `
      -Publisher "Microsoft.Compute" `
      -ExtensionType "CustomScriptExtension" `
      -TypeHandlerVersion "1.10" `
      -ProtectedSettings $Settings
  }