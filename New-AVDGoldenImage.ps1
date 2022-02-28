<#
.SYNOPSIS
	Create Golden Image for the Azure Virtual Desktop endpoints.
.DESCRIPTION
	This script can create the following Golden Images:
		- Windows 10 Enterprise Multi-Session including Office 2019 ProPlus
		- Windows 10 Enterprise Multi-Session including Office 365 ProPlus
		- Windows 10 Enterprise including Office 2019 ProPlus
		- Windows 10 Enterprise including Office 365 ProPlus
.NOTES
	FileName:		New-AVDGoldenImage.ps1
	Version:		1.0
	Author:			Stijn Denruyter
	Created:		24-07-2021
	Updated:		24-07-2021

	Version history:
	1.0 - (24-07-2021)	First version.
#>

[CmdletBinding()]
Param (
	[Parameter(Mandatory = $True)]
	[ValidateNotNullOrEmpty()]
	[String]$OSWindowsVersion,
	[Parameter(Mandatory = $True)]
	[ValidateNotNullOrEmpty()]
	[String]$OSWindowsType,
	[Parameter(Mandatory = $True)]
	[ValidateNotNullOrEmpty()]
	[String]$OfficeVersion,
	[Parameter(Mandatory = $False)]
	[ValidateNotNullOrEmpty()]
	[String]$ApplicationGroup = "",
	[Parameter(Mandatory = $True)]
	[ValidateNotNullOrEmpty()]
	[String]$AVDType
)

#region Declaration variables

$LogFolderPath					= "C:\Logs"
$ConfigFolderPath				= "C:\Config"
$Global:LogFilePath				= $LogFolderPath + "\" + (Get-Item $PSCommandPath).Basename + ".log"

$ErrorActionPreference			= "Stop"

$AppTempTargetDir				= "C:\Windows\Temp"

$ScriptsFolderLocation			= Split-Path -Path $MyInvocation.MyCommand.Definition -Parent

$AzVMLocation					= "westeurope"
$AzVMSubnetName					= "AVD-Subnet"
$AzVMVirtualNetworkID			= "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/Network.Resources/providers/Microsoft.Network/virtualNetworks/xxxxxx.xxxxxx-VirtualNetwork"
$AzVMResourceGroup				= "AVD-Imaging"
$AzVMOSDiskType					= "StandardSSD_LRS"
$AzVMSize						= "Standard_D2s_v3"
$AzVMAdminUserName				= "avdautomationadmin"
$AzVMAdminPassword				= "xxxxxxxxxxxx"
$AzVMPatchMode					= "Manual"
$AzVMEnableHotPatching			= $False

$AzCG							= "AVD_Golden_Images"

$AzVMPrefix						= "AVD-GI"

$OnPremADDomainName				= "domain.local"
$ADCredentialJoinDomainUsername	= "domain\serviceaccount"
$ADCredentialJoinDomainPassword	= "xxxxxxxxxxx"

$MEMCMSiteServerHostName		= "MEMCMSRV.domain.local"
$MEMCMSiteCode					= "MEM"

$OnPremDomainNameServer			= "DC.domain.local"

$MEMCMOSDDeviceCollections		= @(
									("Build and Capture - Automation"),
									("Deploy - Automation")
								)
$MEMCMOSDTaskSequences			= @(
									("Build and Capture Windows 10"),
									("Deploy Windows 10")
								)

#endregion Declaration variables

#region Functions

Function New-FuncAzVMHostname {
	Try {
		Do {
			$Hostname = New-SDMRandomString -Characters "abcdef0123456789" -Length 4
			$Hostname = "$($AzVMPrefix)-$($Hostname)"
		} While (Get-AzVM -Name $Hostname)
		Return $Hostname
	}
	Catch {
		Write-SDMLog -Message "Failed to generate Azure Virtual Machine hostname: $($_.Exception.Message)" -Severity Error
		Break
	}
}

Function New-FuncAzVM {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$AzVMHostname,
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$ImageReferencePublisher,
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$ImageReferenceOffer,
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$ImageReferenceSKU,
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$ImageReferenceVersion
	)
	Try {
		Write-SDMLog -Message "Create Azure Virtual Machine $($AzVMHostname)..." -Severity Info
		New-AzResourceGroupDeployment -Name "AzVM-$($AzVMHostname)-image-deployment" -ResourceGroupName $AzVMResourceGroup -TemplateFile "$($ConfigFolderPath)\azvm_template.json" -TemplateParameterFile "$($ConfigFolderPath)\azvm_parameters.json" -location $AzVMLocation -networkInterfaceName "$($AzVMHostname)-00001" -networkSecurityGroupName "$($AzVMHostname)-nsg" -subnetName $AzVMSubnetName -virtualNetworkId $AzVMVirtualNetworkID -virtualMachineName $AzVMHostname -virtualMachineComputerName $AzVMHostname -virtualMachineRG $AzVMResourceGroup -osDiskType $AzVMOSDiskType -virtualMachineSize $AzVMSize -adminUsername $AzVMAdminUserName -adminPassword (ConvertTo-SecureString -String $AzVMAdminPassword -AsPlainText -Force) -patchMode $AzVMPatchMode -enableHotpatching $AzVMEnableHotPatching -imageReferencePublisher $ImageReferencePublisher -imageReferenceOffer $ImageReferenceOffer -imageReferenceSKU $ImageReferenceSKU -imageReferenceVersion $ImageReferenceVersion | Out-Null
		$Result = (Get-AzResourceGroupDeployment -ResourceGroupName $AzVMResourceGroup -Name "AzVM-$($AzVMHostname)-image-deployment").ProvisioningState
		If ($Result -eq "Succeeded") {
			Write-SDMLog -Message "Successfully created Azure Virtual Machine $($AzVMHostname)" -Severity Info
		}
		Else {
			Throw
		}
	}
	Catch {
		Write-SDMLog -Message "Failed to create Azure Virtual Machine $($AzVMHostname): $($_.Exception.Message)" -Severity Error
		Break
	}
}

Function Restart-FuncAzVM {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$AzVMHostname
	)
	Try {
		Write-SDMLog -Message "Restart Azure Virtual Machine $($AzVMHostname)..." -Severity Info
		$Result = (Restart-AzVM -ResourceGroupName $AzVMResourceGroup -Name $AzVMHostname).Status
		If ($Result -eq "Succeeded") {
			Write-SDMLog -Message "Successfully restarted Azure Virtual Machine $($AzVMHostname)" -Severity Info
		}
		Else {
			Throw
		}
	}
	Catch {
		Write-SDMLog -Message "Failed to restart Azure Virtual Machine $($AzVMHostname): $($_.Exception.Message)" -Severity Error
		Break
	}
}

Function Stop-FuncAzVM {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$AzVMHostname
	)
	Try {
		Write-SDMLog -Message "Stop Azure Virtual Machine $($AzVMHostname)..." -Severity Info
		$Result = (Stop-AzVM -ResourceGroupName $AzVMResourceGroup -Name $AzVMHostname -Force).Status
		If ($Result -eq "Succeeded") {
			Write-SDMLog -Message "Successfully stopped Azure Virtual Machine $($AzVMHostname)" -Severity Info
		}
		Else {
			Throw
		}
	}
	Catch {
		Write-SDMLog -Message "Failed to stop Azure Virtual Machine $($AzVMHostname): $($_.Exception.Message)" -Severity Error
		Break
	}
}

Function Remove-FuncAzVM {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$AzVMHostname
	)
	Try {
		Write-SDMLog -Message "Cleanup resources for $($AzVMHostname)..." -Severity Info
		Try {
			Write-SDMLog -Message "Remove Azure Virtual Machine $($AzVMHostname)..." -Severity Info
			Get-AzResource -TagName "AzVM" -TagValue $AzVMHostname | Where-Object {$_.ResourceType -eq "Microsoft.Compute/virtualMachines"} | Remove-AzResource -Force
			Get-AzResource -TagName "AzVM" -TagValue $AzVMHostname | Where-Object {$_.ResourceType -eq "Microsoft.Network/networkInterfaces"} | Remove-AzResource -Force
			Get-AzResource -TagName "AzVM" -TagValue $AzVMHostname | Where-Object {$_.ResourceType -eq "Microsoft.Network/networkSecurityGroups"} | Remove-AzResource -Force
			Get-AzResource -TagName "AzVM" -TagValue $AzVMHostname | Where-Object {$_.ResourceType -eq "Microsoft.Compute/disks"} | Remove-AzResource -Force
			Write-SDMLog -Message "Successfully removed Azure Virtual Machine $($AzVMHostname)" -Severity Info
		}
		Catch {
			Write-SDMLog -Message "Failed to remove Azure Virtual Machine $($AzVMHostname): $($_.Exception.Message)" -Severity Error
			Break
		}
		Try {
			Write-SDMLog -Message "Remove computer object $($AzVMHostname) from on-premises Active Directory $($OnPremADDomainName)..." -Severity Info
			Get-ADComputer -Identity $AzVMHostname | Remove-ADObject -Recursive -Confirm:$false
			Write-SDMLog -Message "Successfully removed computer object $($AzVMHostname) from on-premises Active Directory $($OnPremADDomainName)" -Severity Info
		}
		Catch {
			Write-SDMLog -Message "Failed to remove computer object $($AzVMHostname) from on-premises Active Directory $($OnPremADDomainName): $($_.Exception.Message)" -Severity Error
			Break
		}
		Try {
			Write-SDMLog -Message "Remove dns record $($AzVMHostname) from on-premises domain $($OnPremADDomainName)..." -Severity Info
			Get-DnsServerResourceRecord -ComputerName $OnPremDomainNameServer -ZoneName $OnPremADDomainName | Where-Object {$_.HostName -eq $AzVMHostname} | Remove-DnsServerResourceRecord -ComputerName $OnPremDomainNameServer -ZoneName $OnPremADDomainName -Force
			Write-SDMLog -Message "Successfully removed dns record $($AzVMHostname) from on-premises domain $($OnPremADDomainName)" -Severity Info
		}
		Catch {
			Write-SDMLog -Message "Failed to remove dns record $($AzVMHostname) from on-premises domain $($OnPremADDomainName): $($_.Exception.Message)" -Severity Error
			Break
		}
		Try {
			Write-SDMLog -Message "Remove computer object $($AzVMHostname) from Azure Active Directory..." -Severity Info
			Get-AzureADDevice -SearchString $AzVMHostname | Remove-AzureADDevice
			Write-SDMLog -Message "Successfully removed computer object $($AzVMHostname) from Azure Active Directory" -Severity Info
		}
		Catch {
			Write-SDMLog -Message "Failed to remove computer object $($AzVMHostname) from Azure Active Directory: $($_.Exception.Message)" -Severity Error
			Break
		}
		Try {
			Write-SDMLog -Message "Remove object $($AzVMHostname) from MEMCM..." -Severity Info
			Mount-SDMMEMCMSiteCode -MEMCMServer $MEMCMSiteServerHostName -MEMCMSiteCode $MEMCMSiteCode
			If (-Not ($MEMCMSiteCode[-1] -eq ":")) {
					$MEMCMSiteCodeWithSuffix = "$($MEMCMSiteCode):"
			}
			Else {
				$MEMCMSiteCodeWithSuffix = $MEMCMSiteCode
				$MEMCMSiteCode = $MEMCMSiteCode -Replace ".$"
			}
			Set-Location -Path $MEMCMSiteCodeWithSuffix
			Get-CMDevice -Name $AzVMHostname | Remove-CMDevice -Force
			Write-SDMLog -Message "Successfully removed object $($AzVMHostname) from MEMCM" -Severity Info
		}
		Catch {
			Write-SDMLog -Message "Failed to remove object $($AzVMHostname) from MEMCM: $($_.Exception.Message)" -Severity Error
			Break
		}	
	}
	Catch {
		Write-SDMLog -Message "Failed to cleanup resources for $($AzVMHostname): $($_.Exception.Message)" -Severity Error
		Break
	}
}

Function Enable-FuncRemotePS {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$AzVMHostname
	)
	Try {
		Write-SDMLog -Message "Enable Remote PowerShell on Azure Virtual Machine $($AzVMHostname)..." -Severity Info
		$Result = (Invoke-AzVMRunCommand -ResourceGroupName $AzVMResourceGroup -VMName $AzVMHostname -CommandId EnableRemotePS).Status
		If ($Result -eq "Succeeded") {
			Write-SDMLog -Message "Successfully enabled Remote PowerShell on Azure Virtual Machine $($AzVMHostname)" -Severity Info
		}
		Else {
			Throw
		}
	}
	Catch {
		Write-SDMLog -Message "Failed to enable Remote PowerShell on Azure Virtual Machine $($AzVMHostname): $($_.Exception.Message)" -Severity Error
		Break	
	}
}

Function Join-FuncOnPremADDomain {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$AzVMHostname
	)
	Try {
		Write-SDMLog -Message "Join Azure Virtual Machine $($AzVMHostname) to on-premises domain $($OnPremADDomainName)..." -Severity Info
		$Result = (Invoke-AzVMRunCommand -ResourceGroupName $AzVMResourceGroup -VMName $AzVMHostname -CommandId RunPowerShellScript -ScriptPath "$($ScriptsFolderLocation)\Join-OnPremADDomain.ps1" -Parameter @{AzVMHostname = $AzVMHostname; OnPremADDomainName = $OnPremADDomainName; ADCredentialJoinDomainUsername = $ADCredentialJoinDomainUsername; ADCredentialJoinDomainPassword = $ADCredentialJoinDomainPassword}).Status
		If ($Result -eq "Succeeded") {
			Write-SDMLog -Message "Successfully joined Azure Virtual Machine $($AzVMHostname) to on-premises domain $($OnPremADDomainName)" -Severity Info
		}
		Else {
			Throw
		}
	}
	Catch {
		Write-SDMLog -Message "Failed to join Azure Virtual Machine $($AzVMHostname) to on-premises domain $($OnPremADDomainName): $($_.Exception.Message)" -Severity Error
		Break
	}
}

Function Install-FuncPSADTApplication {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$AzVMHostname,
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$ApplicationName,
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$SourcesPath
	)
	Write-SDMLog -Message "Installing $($ApplicationName) on Azure Virtual Machine $($AzVMHostname)..." -Severity Info
	Try {
		Do {
			$TargetDir = "$($AppTempTargetDir)\" + (New-SDMRandomString -Characters "ABCDEF0123456789" -Length 8) + "-" + (New-SDMRandomString -Characters "ABCDEF0123456789" -Length 4) + "-" + (New-SDMRandomString -Characters "ABCDEF0123456789" -Length 4) + "-" + (New-SDMRandomString -Characters "ABCDEF0123456789" -Length 4) + "-" + (New-SDMRandomString -Characters "ABCDEF0123456789" -Length 12)
			$TargetDirUNC = "\\$($AzVMHostname).$($OnPremADDomainName)\" + $TargetDir.Replace(":", "$")
		} While (Test-Path -Path "filesystem::$($TargetDirUNC)")
		Write-SDMLog -Message "Copy PSADT source files from $($SourcesPath) to $($TargetDir) on Azure Virtual Machine $($AzVMHostname)..." -Severity Info
		Copy-Item -Path "filesystem::$($SourcesPath)" -Destination "filesystem::$($TargetDirUNC)" -Recurse
	}
	Catch {
		Write-SDMLog -Message "Failed to copy PSADT source files from $($SourcesPath) to $($TargetDir) on Azure Virtual Machine $($AzVMHostname): $($_.Exception.Message)" -Severity Error
		Break
	}
	Try {
		Write-SDMLog -Message "Executing $($TargetDir)\Deploy-Application.exe on Azure Virtual Machine $($AzVMHostname)..." -Severity Info
		$Result = (Invoke-AzVMRunCommand -ResourceGroupName $AzVMResourceGroup -VMName $AzVMHostname -CommandId RunPowerShellScript -ScriptPath "$($ScriptsFolderLocation)\Install-PSADTApplication.ps1" -Parameter @{TargetDir = $TargetDir}).Status
		If ($Result -eq "Succeeded") {
			Write-SDMLog -Message "Successfully installed $($ApplicationName) on Azure Virtual Machine $($AzVMHostname)" -Severity Info
		}
		Else {
			Throw
		}
	}
	Catch {
		Write-SDMLog -Message "Failed to execute $($TargetDir)\Deploy-Application.exe on Azure Virtual Machine $($AzVMHostname): $($_.Exception.Message)" -Severity Error
		Break
	}
}

Function Uninstall-FuncPSADTApplication {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$AzVMHostname,
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$ApplicationName,
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$SourcesPath
	)
	Write-SDMLog -Message "Uninstalling $($ApplicationName) from Azure Virtual Machine $($AzVMHostname)..." -Severity Info
	Try {
		Do {
			$TargetDir = "$($AppTempTargetDir)\" + (New-SDMRandomString -Characters "ABCDEF0123456789" -Length 8) + "-" + (New-SDMRandomString -Characters "ABCDEF0123456789" -Length 4) + "-" + (New-SDMRandomString -Characters "ABCDEF0123456789" -Length 4) + "-" + (New-SDMRandomString -Characters "ABCDEF0123456789" -Length 4) + "-" + (New-SDMRandomString -Characters "ABCDEF0123456789" -Length 12)
			$TargetDirUNC = "\\$($AzVMHostname).$($OnPremADDomainName)\" + $TargetDir.Replace(":", "$")
		} While (Test-Path -Path "filesystem::$($TargetDirUNC)")
		Write-SDMLog -Message "Copy PSADT source files from $($SourcesPath) to $($TargetDir) on Azure Virtual Machine $($AzVMHostname)..." -Severity Info
		Copy-Item -Path "filesystem::$($SourcesPath)" -Destination "filesystem::$($TargetDirUNC)" -Recurse
	}
	Catch {
		Write-SDMLog -Message "Failed to copy PSADT source files from $($SourcesPath) to $($TargetDir) on Azure Virtual Machine $($AzVMHostname): $($_.Exception.Message)" -Severity Error
		Break
	}
	Try {
		Write-SDMLog -Message "Executing $($TargetDir)\Deploy-Application.exe on Azure Virtual Machine $($AzVMHostname)..." -Severity Info
		$Result = (Invoke-AzVMRunCommand -ResourceGroupName $AzVMResourceGroup -VMName $AzVMHostname -CommandId RunPowerShellScript -ScriptPath "$($ScriptsFolderLocation)\Uninstall-PSADTApplication.ps1" -Parameter @{TargetDir = $TargetDir}).Status
		If ($Result -eq "Succeeded") {
			Write-SDMLog -Message "Successfully uninstalled $($ApplicationName) from Azure Virtual Machine $($AzVMHostname)" -Severity Info
		}
		Else {
			Throw
		}
	}
	Catch {
		Write-SDMLog -Message "Failed to execute $($TargetDir)\Deploy-Application.exe on Azure Virtual Machine $($AzVMHostname): $($_.Exception.Message)" -Severity Error
		Break
	}
}

Function Test-FuncMEMCMDeviceExists {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$Name,
		[Parameter(Mandatory = $False)]
		[ValidateNotNullOrEmpty()]
		[Int]$Retry = 0
	)
	Write-SDMLog -Message "Check if MEMCM device $($Name) exists..." -Severity Info
	Mount-SDMMEMCMSiteCode -MEMCMServer $MEMCMSiteServerHostName -MEMCMSiteCode $MEMCMSiteCode
	Try {
		If (-Not ($MEMCMSiteCode[-1] -eq ":")) {
			$MEMCMSiteCodeWithSuffix = "$($MEMCMSiteCode):"
		}
		Else {
			$MEMCMSiteCodeWithSuffix = $MEMCMSiteCode
			$MEMCMSiteCode = $MEMCMSiteCode -Replace ".$"
		}
		Set-Location -Path $MEMCMSiteCodeWithSuffix
	}
	Catch {
		Write-SDMLog -Message "Failed to set the MEMCM site code to $($MEMCMSiteCode): $($_.Exception.Message)" -Severity Error
		Break
	}
	Try {
		If (-Not (Test-SDMMEMCMDeviceExists -Name $Name)) {
			If ($Retry -gt 0) {
				$Retries = $Retry
				Do {
					Write-SDMLog -Message "MEMCM device $($Name) does not exist: retrying in 60 seconds..." -Severity Warning
					$Retries = $Retries - 1
					Start-Sleep -Seconds 60
				} Until ((Test-SDMMEMCMDeviceExists -Name $Name) -or ($Retries -le 0))
				If ($Retries -le 0) {
					Write-SDMLog -Message "MEMCM device $($Name) does not exist" -Severity Error
					Throw
				}
				Else {
					Write-SDMLog -Message "MEMCM device $($Name) exists" -Severity Info
				}
			}
			Else {
				Write-SDMLog -Message "MEMCM device $($Name) does not exist" -Severity Error
				Throw
			}
		}
		Else {
			Write-SDMLog -Message "MEMCM device $($Name) exists" -Severity Info
		}
	}
	Catch {
		Write-SDMLog -Message "Failed to check if MEMCM device $($Name) exists: $($_.Exception.Message)" -Severity Error
		Break
	}
}

Function Start-FuncTaskSequence {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$AzVMHostname,
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$TaskSequenceName,
		[Parameter(Mandatory = $False)]
		[ValidateNotNullOrEmpty()]
		[Int]$Retry = 0
	)
	Write-SDMLog -Message "Starting $($TaskSequenceName) on Azure Virtual Machine $($AzVMHostname)..." -Severity Info
	$ExitLoop = $False
	$RetryCount = 30
	Do {
		Try {
			$Result = Get-WmiObject -Class "CCM_SoftwareDistribution" -ComputerName $AzVMHostname -Namespace "root\ccm\policy\machine\actualconfig" | Where-Object {$_.PKG_Name -eq $TaskSequenceName}
			If (-Not ($Result)) {
				If ($Retry -gt 0) {
					$Retries = $Retry
					Invoke-WmiMethod -Class "SMS_Client" -ComputerName $AzVMHostname -Namespace "root\ccm" -Name TriggerSchedule "{00000000-0000-0000-0000-000000000021}" | Out-Null
					Do {
						Write-SDMLog -Message "MEMCM Task Sequence $($TaskSequence) not assigned to Azure Virtual Machine $($AzVMHostname): retrying in 30 seconds..." -Severity Warning
						$Retries = $Retries - 1
						Start-Sleep -Seconds 30
					} Until ((Get-WmiObject -Class "CCM_SoftwareDistribution" -ComputerName $AzVMHostname -Namespace "root\ccm\policy\machine\actualconfig" | Where-Object {$_.PKG_Name -eq $TaskSequenceName}) -or ($Retries -le 0))
					If ($Retries -le 0) {
						Write-SDMLog -Message "MEMCM Task Sequence $($TaskSequence) not assigned to Azure Virtual Machine $($AzVMHostname)" -Severity Error
						Throw
					}
					Else {
						$SoftwareDistributionPolicy = Get-WmiObject -Class "CCM_SoftwareDistribution" -ComputerName $AzVMHostname -Namespace "root\ccm\policy\machine\actualconfig" | Where-Object {$_.PKG_Name -eq $TaskSequenceName}
					}
				}
				Else {
					Write-SDMLog -Message "MEMCM Task Sequence $($TaskSequence) not assigned to Azure Virtual Machine $($AzVMHostname)" -Severity Error
					Throw
				}
			}
			Else {
				$SoftwareDistributionPolicy = Get-WmiObject -Class "CCM_SoftwareDistribution" -ComputerName $AzVMHostname -Namespace "root\ccm\policy\machine\actualconfig" | Where-Object {$_.PKG_Name -eq $TaskSequenceName}
			}
			$ExitLoop = $True
		}
		Catch {
			If ($RetryCount -eq 0) {
				Write-SDMLog -Message "Failed to start Task Sequence $($TaskSequenceName) on Azure Virtual Machine $($AzVMHostname): $($_.Exception.Message)" -Severity Error
				Break
			}
			Else {
				Write-SDMLog -Message "Failed to start Task Sequence $($TaskSequenceName) on Azure Virtual Machine $($AzVMHostname): retrying in 30 seconds..." -Severity Warning
				Start-Sleep -Seconds 30
				$RetryCount = $RetryCount - 1
			}
		}
	} While($ExitLoop -eq $False)
	Start-Sleep -Seconds 60
	Write-SDMLog -Message "Execute Task Sequence $($TaskSequenceName) on Azure Virtual Machine $($AzVMHostname)..." -Severity Info
	$ExitLoop = $False
	$RetryCount = 30
	Do {
		Try {
			$ScheduleID = (Get-WmiObject -Class "CCM_Scheduler_History" -ComputerName $AzVMHostname -Namespace "root\ccm\scheduler" | Where-Object {$_.ScheduleID -like "*$($SoftwareDistributionPolicy.PKG_PackageID)*"}).ScheduleID
			$TaskSequencePolicy = Get-WmiObject -Class "CCM_TaskSequence" -ComputerName $AzVMHostname -Namespace "root\ccm\policy\machine\actualconfig" | Where-Object {$_.ADV_AdvertisementID -eq $SoftwareDistributionPolicy.ADV_AdvertisementID}
			If ($TaskSequencePolicy.ADV_RepeatRunBehavior -notlike "RerunAlways") {
				$TaskSequencePolicy.ADV_RepeatRunBehavior = "RerunAlways"
				$TaskSequencePolicy.Put()
			}
			$TaskSequencePolicy.Get()
			$TaskSequencePolicy.ADV_MandatoryAssignments = $True
			$TaskSequencePolicy.Put() | Out-Null
			Invoke-WmiMethod -Class "SMS_Client" -ComputerName $AzVMHostname -Namespace "root\ccm" -Name "TriggerSchedule" -ArgumentList $ScheduleID | Out-Null
			Write-SDMLog -Message "Waiting for MEMCM Task Sequence $($TaskSequenceName) on Azure Virtual Machine $($AzVMHostname) to finish..." -Severity Info
			Do {
				If (-Not (Test-Path -Path "filesystem::\\$($AzVMHostname)\C$")) {
					$Retries = 10
					Do {
						$Retries = $Retries - 1
						Start-Sleep -Seconds 60
					} Until ((Test-Path -Path "filesystem::\\$($AzVMHostname)\C$") -or ($Retries -le 0))
					If ($Retries -le 0) {
						Write-SDMLog -Message "Failed to connect to filesystem on Azure Virtual Machine $($AzVMHostname). Reboot Azure Virtual Machine $($AzVMHostname)..." -Severity Warning
						Restart-FuncAzVM -AzVMHostname $AzVMHostname
					}
				}
				$Result = Get-CMPackageDeploymentStatus -Name $TaskSequenceName | Get-CMDeploymentStatusDetails | Where-Object {$_.DeviceName -eq $AzVMHostname} -ErrorAction SilentlyContinue
				Start-Sleep -Seconds 60
			} Until ($Result.StatusDescription -eq "The task sequence manager successfully completed execution of the task sequence")
			Write-SDMLog -Message "MEMCM Task Sequence $($TaskSequenceName) finished on Azure Virtual Machine $($AzVMHostname)" -Severity Info
			$ExitLoop = $True
		}
		Catch {
			If ($RetryCount -eq 0) {
				Write-SDMLog -Message "Failed to execute Task Sequence $($TaskSequenceName) on Azure Virtual Machine $($AzVMHostname): $($_.Exception.Message)" -Severity Error
				Break
			}
			Else {
				Write-SDMLog -Message "Failed to execute Task Sequence $($TaskSequenceName) on Azure Virtual Machine $($AzVMHostname): retrying in 30 seconds..." -Severity Warning
				Start-Sleep -Seconds 30
				$RetryCount = $RetryCount - 1
			}
		}
	} While($ExitLoop -eq $False)
}

Function Resume-FuncInstallMandatoryApplication {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$AzVMHostname,
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$ApplicationName
	)
	Try {
		Write-SDMLog -Message "Resume installation $($ApplicationName) on Azure Virtual Machine $($AzVMHostname)..." -Severity Info
		$Application = Get-WmiObject -Class "CCM_Application" -ComputerName $AzVMHostname -Namespace "root\ccm\ClientSDK" | Where-Object {$_.Name -eq $ApplicationName}
		Invoke-Command -ComputerName $AzVMHostName {param ($Application) ([wmiclass]'ROOT\ccm\ClientSdk:CCM_Application').Install($Application.Id, $Application.Revision, $Application.IsMachineTarget, 0, 'Normal', $False)} -ArgumentList $Application | Out-Null
	}
	Catch {
		Write-SDMLog -Message "Failed to resume installation $($ApplicationName) on Azure Virtual Machine $($AzVMHostname): $($_.Exception.Message)" -Severity Error
		Break
	}
}

Function Install-FuncMandatoryApplications {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$AzVMHostname,
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$MEMCMDeviceCollection,
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$MEMCMSiteServerHostName,
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$MEMCMSiteCode
	)
	Write-SDMLog -Message "Install mandatory applications on Azure Virtual Machine $($AzVMHostname)..." -Severity Info
	$ExitLoop = $False
	$RetryCount = 30
	Do {
		Try {
			Add-SDMMEMCMDeviceCollectionDirectMembershipRule -Name $AzVMHostname -DeviceCollection $MEMCMDeviceCollection -MEMCMServer $MEMCMSiteServerHostName -MEMCMSiteCode $MEMCMSiteCode
			Invoke-WmiMethod -Class "SMS_Client" -ComputerName $AzVMHostname -Namespace "root\ccm" -Name TriggerSchedule "{00000000-0000-0000-0000-000000000021}" | Out-Null
			Write-SDMLog -Message "Wait for the mandatory applications to install on Azure Virtual Machine $($AzVMHostname)..." -Severity Info
			Mount-SDMMEMCMSiteCode -MEMCMServer $MEMCMSiteServerHostName -MEMCMSiteCode $MEMCMSiteCode
			Try {
				If (-Not ($MEMCMSiteCode[-1] -eq ":")) {
					$MEMCMSiteCodeWithSuffix = "$($MEMCMSiteCode):"
				}
				Else {
					$MEMCMSiteCodeWithSuffix = $MEMCMSiteCode
					$MEMCMSiteCode = $MEMCMSiteCode -Replace ".$"
				}
				Set-Location -Path $MEMCMSiteCodeWithSuffix
			}
			Catch {
				Write-SDMLog -Message "Failed to set the MEMCM site code to $($MEMCMSiteCode): $($_.Exception.Message)" -Severity Error
				Break
			}
			$PublishedApplications = (Get-CMApplicationDeployment -CollectionName $MEMCMDeviceCollection | Sort-Object ApplicationName).ApplicationName
			Do {
				$NumberToBeInstalled = 0
				$NumberInstalled = 0
				$NumberFailed = 0
				$NumberAssigned = 0
				$AvailableApplications = Get-WmiObject -Query "SELECT * FROM CCM_Application" -Namespace "ROOT\ccm\ClientSDK" -ComputerName $AzVMHostName
				ForEach ($PublishedApplication In $PublishedApplications) {
					ForEach ($AvailableApplication In $AvailableApplications) {
						If (($PublishedApplication -like "*$($AvailableApplication.Name)*") -and ($AvailableApplication.EvaluationState -ne 0) -and ($AvailableApplication.EvaluationState -ne 2)) {
							If ($AvailableApplication.EvaluationState -eq "4") {
								Resume-FuncInstallMandatoryApplication -AzVMHostname $AzVMHostName -ApplicationName $AvailableApplication.Name
							}
							If (($AvailableApplication.EvaluationState -eq "3") -or ($AvailableApplication.EvaluationState -eq "5") -or ($AvailableApplication.EvaluationState -eq "6") -or ($AvailableApplication.EvaluationState -eq "12") -or ($AvailableApplication.EvaluationState -eq "26")) {
								$NumberToBeInstalled = $NumberToBeInstalled + 1
							}
							ElseIf (($AvailableApplication.EvaluationState -eq "1") -or ($AvailableApplication.EvaluationState -eq "27")) {
								$NumberInstalled = $NumberInstalled + 1
							}
							ElseIf ($AvailableApplication.EvaluationState -eq "1") {
								$NumberInstalled = $NumberInstalled + 1
							}
							ElseIf ($AvailableApplication.EvaluationState -eq "4") {
								$NumberFailed = $NumberFailed + 1
							}
							$NumberAssigned = $NumberAssigned + 1
							Break
						}
					}
				}
				Write-SDMLog -Message "Installed: $($NumberInstalled) of $($NumberAssigned) with $($NumberFailed) failed" -Severity Info
				Start-Sleep -Seconds 600
			} Until (($NumberInstalled -eq $NumberAssigned) -and $NumberInstalled -gt 0)
			$ExitLoop = $True
		}
		Catch {
			If ($RetryCount -eq 0){
				Write-SDMLog -Message "Failed to install mandatory applications on Azure Virtual Machine $($AzVMHostname): $($_.Exception.Message)" -Severity Error
				Break
			}
			Else {
				Write-SDMLog -Message "Failed to install mandatory applications on Azure Virtual Machine $($AzVMHostname): retrying in 30 seconds..." -Severity Warning
				Start-Sleep -Seconds 30
				$RetryCount = $RetryCount - 1
			}
		}
	} While($ExitLoop -eq $False)
}

Function Copy-FuncLogFiles {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$AzVMHostname,
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$SourceLogFilePath,
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$TargetLogFilePath
	)
	Try {
		Write-SDMLog -Message "Copy logs from $($SourceLogFilePath) to $($TargetLogFilePath) from Azure Virtual Machine $($AzVMHostname)..." -Severity Info
		$SourceLogFilePath = "\\$($AzVMHostname).$($OnPremADDomainName)\" + $SourceLogFilePath.Replace(":", "$")
		Copy-Item -Path "filesystem::$($SourceLogFilePath)" -Destination $TargetLogFilePath -Recurse
		Write-SDMLog -Message "Successfully copied logs from $($SourceLogFilePath) to $($TargetLogFilePath) from Azure Virtual Machine $($AzVMHostname)..." -Severity Info
	}
	Catch {
		Write-SDMLog -Message "Failed to copy logs from $($SourceLogFilePath) to $($TargetLogFilePath) from Azure Virtual Machine $($AzVMHostname): $($_.Exception.Message)" -Severity Error
		Break	
	}
}

Function Start-FuncSysPrep {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$AzVMHostname
	)
	Try {
		Write-SDMLog -Message "Sysprep Azure Virtual Machine $($AzVMHostname)..." -Severity Info
		$Result = (Invoke-AzVMRunCommand -ResourceGroupName $AzVMResourceGroup -VMName $AzVMHostname -CommandId RunPowerShellScript -ScriptPath "$($ScriptsFolderLocation)\Start-Sysprep.ps1").Status
		If ($Result -eq "Succeeded") {
			Write-SDMLog -Message "Succeeded Sysprep Azure Virtual Machine $($AzVMHostname)" -Severity Info
		}
		Else {
			Throw
		}	
	}
	Catch {
		Write-SDMLog -Message "Failed to Sysprep Azure Virtual Machine $($AzVMHostname): $($_.Exception.Message)" -Severity Error
		Break	
	}
}

Function New-FuncAzCGImageVersion {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$AzVMHostname,
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$AzCGImageDefinitionName
	)
	Try {
		Write-SDMLog -Message "Create Azure Compute Gallery Image Definition Version for Azure Virtual Machine $($AzVMHostname)..." -Severity Info
		$VM = Get-AzVM -Name $AzVMHostname -ResourceGroupName $AzVMResourceGroup
		$Version = Get-Date -Format "yyyy.MM.dd"
		Write-SDMLog -Message "Create version $($Version) in $($AzCGImageDefinitionName)-UAT and set it as the default image..." -Severity Info
		$Result = (New-AzGalleryImageVersion -ResourceGroupName $AzVMResourceGroup -GalleryName $AzCG -GalleryImageDefinitionName "$($AzCGImageDefinitionName)-UAT" -Location $AzVMLocation -SourceImageId $VM.Id -GalleryImageVersionName $Version).ProvisioningState
		If ($Result -eq "Succeeded") {
			Write-SDMLog -Message "Successfully created version $($Version) in $($AzCGImageDefinitionName)-UAT and set it as the default image" -Severity Info
		}
		Else {
			Throw
		}
		Write-SDMLog -Message "Create version $($Version) in $($AzCGImageDefinitionName)-PRD..." -Severity Info
		$Result = (New-AzGalleryImageVersion -ResourceGroupName $AzVMResourceGroup -GalleryName $AzCG -GalleryImageDefinitionName "$($AzCGImageDefinitionName)-PRD" -Location $AzVMLocation -SourceImageId $VM.Id -GalleryImageVersionName $Version -PublishingProfileExcludeFromLatest).ProvisioningState
		If ($Result -eq "Succeeded") {
			Write-SDMLog -Message "Successfully created version $($Version) in $($AzCGImageDefinitionName)-PRD" -Severity Info
		}
		Else {
			Throw
		}
	}
	Catch {
		Write-SDMLog -Message "Failed to create Azure Compute Gallery Image Definition Version for Azure Virtual Machine $($AzVMHostname): $($_.Exception.Message)" -Severity Error
		Break
	}
}

Function Add-FuncServiceAccountToLocalAdminGroup {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$AzVMHostname
	)
	Try {
		Write-SDMLog -Message "Add DOMAIN\ServiceAccount to the local Administrators group on Azure Virtual Machine $($AzVMHostname)..." -Severity Info
		$Result = (Invoke-AzVMRunCommand -ResourceGroupName $AzVMResourceGroup -VMName $AzVMHostname -CommandId RunPowerShellScript -ScriptPath "$($ScriptsFolderLocation)\Add-ServiceAccountToLocalAdminGroup.ps1").Status
		If ($Result -eq "Succeeded") {
			Write-SDMLog -Message "Successfully added DOMAIN\ServiceAccount to the local Administrators group on Azure Virtual Machine $($AzVMHostname)" -Severity Info
		}
		Else {
			Throw
		}
	}
	Catch {
		Write-SDMLog -Message "Failed to add DOMAIN\ServiceAccount to the local Administrators group on Azure Virtual Machine $($AzVMHostname): $($_.Exception.Message)" -Severity Error
		Break
	}
}

Function Set-FuncAzVMGeneralized {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True)]
		[ValidateNotNullOrEmpty()]
		[String]$AzVMHostname
	)
	Try {
		Write-SDMLog -Message "Set Azure Virtual Machine $($AzVMHostname) to status Generalized..." -Severity Info
		$Result = (Set-AzVM -ResourceGroupName $AzVMResourceGroup -Name $AzVMHostname -Generalized).Status
		If ($Result -eq "Succeeded") {
			Write-SDMLog -Message "Successfully set Azure Virtual Machine $($AzVMHostname) to status Generalized" -Severity Info
		}
		Else {
			Throw
		}
	}
	Catch {
		Write-SDMLog -Message "Failed to set Azure Virtual Machine $($AzVMHostname) to status Generalized: $($_.Exception.Message)" -Severity Error
		Break
	}
}


#endregion Functions

#region Script

Import-Module SDM -Force
Import-SDMMEMCMModule

Switch ($OSWindowsType) {
	"MS"	{
		$ImageReferenceSKUOSType = "evd"
	}
	"SS"	{
		$ImageReferenceSKUOSType = "ent"
	}
}

Switch ($OfficeVersion) {
	"OFFICE2019"	{
		$ImageDefinitionOfficeType = "O2019"
	}
	"OFFICE365"	{
		$ImageDefinitionOfficeType = "O365"
	}
}

Switch ($OSWindowsVersion) {
	"W10_20H2"	{
		$ImageReferencePublisher = "MicrosoftWindowsDesktop"
		$ImageReferenceOffer = "Windows-10"
		$ImageReferenceSKU = "20h2-$($ImageReferenceSKUOSType)-g2"
		$ImageReferenceVersion = "latest"
		$OSWindowsVersion = "20H2"
	}
	"W10_21H2"	{
		$ImageReferencePublisher = "MicrosoftWindowsDesktop"
		$ImageReferenceOffer = "Windows-10"
		$ImageReferenceSKU = "21h2-$($ImageReferenceSKUOSType)-g2"
		$ImageReferenceVersion = "latest"
		$OSWindowsVersion = "21H2"
	}
}

Import-AzContext -Path "$($ConfigFolderPath)\azcontext.json" | Out-Null
$AzVMHostname = New-FuncAzVMHostname
$Global:LogFilePath = $LogFolderPath + "\" + (Get-Item $PSCommandPath).Basename + "-$($AzVMHostname).log"
New-FuncAzVM -AzVMHostname $AzVMHostname -ImageReferencePublisher $ImageReferencePublisher -ImageReferenceOffer $ImageReferenceOffer -ImageReferenceSKU $ImageReferenceSKU -ImageReferenceVersion $ImageReferenceVersion
Enable-FuncRemotePS -AzVMHostname $AzVMHostname
Join-FuncOnPremADDomain -AzVMHostname $AzVMHostname
Add-FuncServiceAccountToLocalAdminGroup -AzVMHostname $AzVMHostname
Restart-FuncAzVM -AzVMHostname $AzVMHostname
Test-SDMComputerConnection -Name $AzVMHostname -Retry 60
Install-FuncPSADTApplication -AzVMHostname $AzVMHostname -ApplicationName "Microsoft MEMCM Client" -SourcesPath "\\domain.local\Packages\Microsoft\MEMCM Client"
Test-FuncMEMCMDeviceExists -Name $AzVMHostname -Retry 30
Add-SDMMEMCMDeviceVariable -Name $AzVMHostname -Variable "VAR-LOCATION" -Value "CLOUD" -MEMCMServer $MEMCMSiteServerHostName -MEMCMSiteCode $MEMCMSiteCode
Add-SDMMEMCMDeviceVariable -Name $AzVMHostname -Variable "VAR-WINDOWSVERSION" -Value $OSWindowsVersion -MEMCMServer $MEMCMSiteServerHostName -MEMCMSiteCode $MEMCMSiteCode
Add-SDMMEMCMDeviceVariable -Name $AzVMHostname -Variable "VAR-OFFICEVERSION" -Value $OfficeVersion -MEMCMServer $MEMCMSiteServerHostName -MEMCMSiteCode $MEMCMSiteCode
Add-SDMMEMCMDeviceVariable -Name $AzVMHostname -Variable "VAR-BUILD" -Value "AVD" -MEMCMServer $MEMCMSiteServerHostName -MEMCMSiteCode $MEMCMSiteCode
Add-SDMMEMCMDeviceVariable -Name $AzVMHostname -Variable "VAR-AVDType" -Value $AVDType -MEMCMServer $MEMCMSiteServerHostName -MEMCMSiteCode $MEMCMSiteCode
ForEach ($MEMCMOSDDeviceCollection In $MEMCMOSDDeviceCollections) {
	Add-SDMMEMCMDeviceCollectionDirectMembershipRule -Name $AzVMHostname -DeviceCollection $MEMCMOSDDeviceCollection -MEMCMServer $MEMCMSiteServerHostName -MEMCMSiteCode $MEMCMSiteCode
}
ForEach ($MEMCMOSDTaskSequence In $MEMCMOSDTaskSequences) {
	Start-FuncTaskSequence -AzVMHostname $AzVMHostname -TaskSequenceName $MEMCMOSDTaskSequence -Retry 500
}
If ($ApplicationGroup) {
	Install-FuncMandatoryApplications -AzVMHostname $AzVMHostname -MEMCMDeviceCollection "AVD-APPS-$($ApplicationGroup)" -MEMCMSiteServerHostName $MEMCMSiteServerHostName -MEMCMSiteCode $MEMCMSiteCode
}
Uninstall-FuncPSADTApplication -AzVMHostname $AzVMHostname -ApplicationName "Microsoft MEMCM Client" -SourcesPath "\\domain.local\Packages\Microsoft\MEMCM Client"
Restart-FuncAzVM -AzVMHostname $AzVMHostname
Test-SDMComputerConnection -Name $AzVMHostname -Retry 60
$TargetLogFilePath = "$($LogFolderPath)\" + (Get-Item $PSCommandPath).Basename + "\$($AzVMHostname)"
Copy-FuncLogFiles -AzVMHostname $AzVMHostname -SourceLogFilePath "C:\Windows\Logs\Software" -TargetLogFilePath $TargetLogFilePath
If ($OSWindowsType -eq "MS") {
	Install-FuncPSADTApplication -AzVMHostname $AzVMHostname -ApplicationName "Citrix Optimizer" -SourcesPath "\\domain.local\Packages\Citrix\Optimizer\"
	Install-FuncPSADTApplication -AzVMHostname $AzVMHostname -ApplicationName "Virtual Desktop Optimization Tool" -SourcesPath "\\domain.local\Packages\The Virtual Desktop Team\Virtual Desktop Optimization Tool"
}
Start-FuncSysPrep -AzVMHostname $AzVMHostname
Stop-FuncAzVM -AzVMHostname $AzVMHostname
Set-FuncAzVMGeneralized -AzVMHostname $AzVMHostname
If ($ApplicationGroup) {
	New-FuncAzCGImageVersion -AzVMHostname $AzVMHostname -AzCGImageDefinitionName "AVD-$($OSWindowsType)-$($ImageDefinitionOfficeType)-$($ApplicationGroup)"
}
Else {
	New-FuncAzCGImageVersion -AzVMHostname $AzVMHostname -AzCGImageDefinitionName "AVD-$($OSWindowsType)-$($ImageDefinitionOfficeType)"
}
Remove-FuncAzVM -AzVMHostname $AzVMHostname

#endregion Script