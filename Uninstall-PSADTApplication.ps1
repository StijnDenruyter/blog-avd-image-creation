[CmdletBinding()]
Param (
	[Parameter(Mandatory = $True)]
	[ValidateNotNullOrEmpty()]
	[String]$TargetDir
)

Start-Process -FilePath "$($TargetDir)\Deploy-Application.exe" -ArgumentList "Uninstall" -Verb RunAs -Wait