New-NetFirewallRule -DisplayName "AVDAutomation_WinRM" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5985,5986
New-NetFirewallRule -DisplayName "AVDAutomation_ICMP" -Direction Inbound -Action Allow -Protocol ICMPv4
New-NetFirewallRule -DisplayName "AVDAutomation_Server" -Direction Inbound -Action Allow -Protocol TCP -RemoteAddress 10.4.121.31