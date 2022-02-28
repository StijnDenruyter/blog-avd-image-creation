[CmdletBinding()]
Param (
	[Parameter(Mandatory = $True)]
	[ValidateNotNullOrEmpty()]
	[String]$AzVMHostname,
	[Parameter(Mandatory = $True)]
	[ValidateNotNullOrEmpty()]
	[String]$OnPremADDomainName,
	[Parameter(Mandatory = $True)]
	[ValidateNotNullOrEmpty()]
	[String]$ADCredentialJoinDomainUsername,
	[Parameter(Mandatory = $True)]
	[ValidateNotNullOrEmpty()]
	[String]$ADCredentialJoinDomainPassword
)

$Password = ConvertTo-SecureString $ADCredentialJoinDomainPassword -AsPlainText -Force
$DomainCredential = New-Object System.Management.Automation.PSCredential($ADCredentialJoinDomainUsername, $Password)
Add-Computer -ComputerName $AzVMHostname -Credential $DomainCredential -DomainName $OnPremADDomainName