[CmdletBinding()]
Param (
	[Parameter(Mandatory = $True)]
	[ValidateNotNullOrEmpty()]
	[String]$TargetDir
)

Start-Process -FilePath "$($TargetDir)\Deploy-Application.exe" -ArgumentList "Install" -Verb RunAs -Wait