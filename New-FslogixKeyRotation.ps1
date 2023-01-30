
[CmdletBinding()]
param (
    [parameter(mandatory = $false)]$fslogixPath = 'HKLM:\Software\FSLogix\Profiles',
    [parameter(mandatory = $false)]$key,
    [parameter(mandatory = $false)]$accountName,
    [parameter(mandatory = $false)]$profileLocation = "C:\ProgramData\FSLogix\Cache",
    [parameter(mandatory = $true)]$primaryEndpoint
)

$fslogixPath = 'HKLM:\Software\FSLogix\Profiles'
New-ItemProperty -Path "HKLM:\Software\FSLogix\Profiles" -Name Enabled -Value 1 -PropertyType DWORD -Force | Out-Null
New-ItemProperty -Path "HKLM:\Software\FSLogix\Profiles" -Name FlipFlopProfileDirectoryName -Value 1 -PropertyType DWORD -Force | Out-Null
Set-ItemProperty -Path "HKLM:\Software\FSLogix\Profiles" -Name 'PreventLoginWithFailure' -Value 1 -Force
Set-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -Name 'PreventLoginWithTempProfile' -Value 1 -Force

$testGroup = Get-localGroupMember -Group 'FSLogix Profile Exclude List' -Member  'BuiltIn\Administrators' -ErrorAction SilentlyContinue | Out-Null
if( $testGroup.Name -notcontains 'BuiltIn\Administrators'){
     Add-LocalGroupMember -Group 'FSLogix Profile Exclude List' -Member 'Administrators' -ErrorAction SilentlyContinue | Out-Null
}
$testGroup2 = Get-localGroupMember -Group 'FSLogix ODFC Exclude List' -Member  'BuiltIn\Administrators' -ErrorAction SilentlyContinue | Out-Null
if( $testGroup2.Name -notcontains 'BuiltIn\Administrators'){
    Add-LocalGroupMember -Group 'FSLogix ODFC Exclude List' -Member 'Administrators' -ErrorAction SilentlyContinue | Out-Null
}

$connectionstring = "DefaultEndpointsProtocol=https;" + "AccountName=$accountName;" + "AccountKey=$key;" + "EndpointSuffix=$primaryEndpoint"

Start-Process -FilePath 'C:\Program Files\FSLogix\Apps\frx.exe' -ArgumentList "add-secure-key -key connectionstring -value $($connectionstring)"
New-ItemProperty -Path $fslogixPath -Force -Name CCDLocations -PropertyType multistring -Value "type=azure,connectionString=|fslogix/connectionstring|"| Out-Null
New-ItemProperty -Path $fslogixPath -Name DeleteLocalProfileWhenVHDShouldApply -Value 1 -PropertyType DWORD -Force | Out-Null
New-ItemProperty -Path HKLM:SYSTEM\CurrentControlSet\Services\frxccd\Parameters -Name CacheDirectory -Value $profileLocation -PropertyType String -Force | Out-Null