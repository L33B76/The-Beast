<#
 Failover planificado de ASR para una VM. Variables de entorno: ASR_DIRECTION (PrimaryToRecovery|RecoveryToPrimary),
 ASR_VAULT_NAME, ASR_VAULT_RG, ASR_VM_NAME, DRY_RUN, AZURE_USE_MSI | AZURE_CLIENT_ID/SECRET/TENANT_ID, AZURE_SUBSCRIPTION_ID.
 NOTA: este script NO hace Commit ni Re-protect. El runbook no los describe, aunque en el ensayo hubo un
       problema de "reprotect". Confirmar con DXC el procedimiento exacto antes de añadirlos.
#>
$ErrorActionPreference = 'Stop'
$dry = $env:DRY_RUN -eq '1'

if ($env:AZURE_USE_MSI -eq 'true') { Connect-AzAccount -Identity | Out-Null }
else {
  $sec = ConvertTo-SecureString $env:AZURE_CLIENT_SECRET -AsPlainText -Force
  Connect-AzAccount -ServicePrincipal -Tenant $env:AZURE_TENANT_ID -Credential (New-Object System.Management.Automation.PSCredential($env:AZURE_CLIENT_ID, $sec)) | Out-Null
}
Set-AzContext -Subscription $env:AZURE_SUBSCRIPTION_ID | Out-Null

$vault = Get-AzRecoveryServicesVault -ResourceGroupName $env:ASR_VAULT_RG -Name $env:ASR_VAULT_NAME
Set-AzRecoveryServicesAsrVaultContext -Vault $vault | Out-Null

$item = $null
foreach ($fabric in Get-AzRecoveryServicesAsrFabric) {
  foreach ($pc in Get-AzRecoveryServicesAsrProtectionContainer -Fabric $fabric) {
    $found = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $pc |
             Where-Object { $_.FriendlyName -eq $env:ASR_VM_NAME }
    if ($found) { $item = $found }
  }
}
if (-not $item) { throw "No se encontró la VM protegida $($env:ASR_VM_NAME) en el vault $($env:ASR_VAULT_NAME)" }
Write-Host "VM $($item.FriendlyName): estado de protección = $($item.ProtectionState), salud = $($item.ReplicationHealth)"

if ($dry) { Write-Host "DRY-RUN: no se lanza el failover ($($env:ASR_DIRECTION))"; exit 0 }

$job = Start-AzRecoveryServicesAsrPlannedFailoverJob -ReplicationProtectedItem $item -Direction $env:ASR_DIRECTION
do {
  Start-Sleep -Seconds 20
  $job = Get-AzRecoveryServicesAsrJob -Job $job
  Write-Host "Job ASR: $($job.State)"
} while ($job.State -in @('NotStarted', 'InProgress'))

if ($job.State -ne 'Succeeded') { throw "El job de ASR terminó en estado $($job.State)" }
Write-Host "Failover ASR completado ($($env:ASR_DIRECTION))"
