[CmdletBinding()]
param (
    [parameter(mandatory = $true)]$HostpoolName,
    [parameter(mandatory = $true)]$Environment,
    [parameter(mandatory = $true)]$location,
    [parameter(mandatory = $true)]$storageAcctName,
    [parameter(mandatory = $true)]$storageAcctRgName,
    [parameter(mandatory = $true)]$account
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
$vms = "vmsmtpvap002"

# get storage account key
$sa = Get-AzStorageAccount -StorageAccountName $storageAcctName -ResourceGroupName $storageAcctRgName
$oldKeys = Get-AzStorageAccountKey -ResourceGroupName $sa.ResourceGroupName -Name $sa.StorageAccountName
$endpoint = $sa.PrimaryEndpoints
$primaryEndpoint = ($endpoint.blob.Split("https://$($sa.storageAccountName).blob.")[1]).trim('/')
$accountName = $account

$fileUris = @("https://raw.githubusercontent.com/mikedzikowski/FSLogixKeyRotation/main/New-FslogixKeyRotation.ps1")
$key2Settings = @{"fileUris" = $fileUris; "commandToExecute" = "powershell -ExecutionPolicy Unrestricted -File New-FslogixKeyRotation.ps1 -key $($oldkeys[1].value) -primaryEndpoint $primaryEndpoint -accountName $accountName"};
$settings = @{"timestamp" = (get-date).ToUniversalTime().ToString('yyMMddTHHmmss')};

# Send out key2
$vms | ForEach-Object -Parallel {
    $virtualMachine = (Get-AzVM -VMName $_.split('.')[0])
    Set-AzVMExtension -ResourceGroupName $virtualMachine.ResourceGroupName `
        -Location $virtualMachine.Location `
        -VMName $virtualMachine.Name `
        -Name "CustomScriptExtension" `
        -Publisher "Microsoft.Compute" `
        -ExtensionType "CustomScriptExtension" `
        -TypeHandlerVersion "1.10" `
        -Settings $settings `
        -ProtectedSettings $key2Settings
}

# Rotate key1
$rotateKey1 = New-AzStorageAccountKey -ResourceGroupName $sa.ResourceGroupName -Name $sa.StorageAccountName -KeyName key1 -Verbose
Write-Host "Rotating: $($rotateKey1.Keys.keyname[0])"
$newKey1 = Get-AzStorageAccountKey -ResourceGroupName $sa.ResourceGroupName -Name $sa.StorageAccountName
$key1Settings = @{"fileUris" = $fileUris;"commandToExecute" = "powershell -ExecutionPolicy Unrestricted -File New-FslogixKeyRotation.ps1 -key $($newkey1[0].Value). -accountName $accountName -primaryEndpoint $primaryEndpoint"}
$settings = @{"timestamp" = (get-date).ToUniversalTime().ToString('yyMMddTHHmmss')};

# Send rotated key1 back out to AVD
$vms | ForEach-Object -Parallel {
    $virtualMachine = (Get-AzVM -VMName $_.split('.')[0])
    Set-AzVMExtension -ResourceGroupName $virtualMachine.ResourceGroupName `
        -Location $virtualMachine.Location `
        -VMName $virtualMachine.Name `
        -Name "CustomScriptExtension" `
        -Publisher "Microsoft.Compute" `
        -ExtensionType "CustomScriptExtension" `
        -TypeHandlerVersion "1.10" `
        -Settings $settings `
        -ProtectedSettings $key1Settings
}

# Rotate key2
Write-Host "Rotating: $($rotateKey2.Keys.keyname[1])"
$rotateKey2 = New-AzStorageAccountKey -ResourceGroupName $sa.ResourceGroupName -Name $sa.StorageAccountName -KeyName key2 -Verbose
