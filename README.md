# ucs-powertool-samples
Sample UCS PowerTool scripts

To try out the scripts create a ucs.xml and ucs.key file using the following method:
```
$handle1 = Connect-Ucs -Name <your-ucs-ip-address>

Export-UcsPSSession -LiteralPath ucs.xml

ConvertTo-SecureString -String "<your-password>" -AsPlainText -Force | ConvertFrom-SecureString | Out-File ucs.key

Disconnect-Ucs -Ucs $handle

```

