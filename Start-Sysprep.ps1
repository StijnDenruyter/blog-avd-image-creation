Start-Process -FilePath "sysprep.exe" -WorkingDirectory "C:\Windows\System32\Sysprep" -ArgumentList "/generalize /oobe /shutdown" -Verb RunAs -Wait