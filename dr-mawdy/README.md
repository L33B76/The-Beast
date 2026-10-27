# Automatización DR Mawdy LATAM

Automatiza el runbook `Runbook_DR_Mawdy_LATAM_v3_1_1.xlsx` con **Bitbucket Pipelines**.

**Qué está automatizado y qué no.** Hay 25 tareas automáticas y 21 manuales (Zeus/KMM, despliegues de CAP,
monitorización de Kyndryl, pruebas de negocio). Las manuales no desaparecen: el pipeline las **anuncia por Teams,
se detiene y espera** a que el responsable pulse un step "✔ Confirmar". Cada confirmación queda registrada (quién y cuándo).

## Arquitectura

| Pieza | Fichero | Función |
|---|---|---|
| Fuente de verdad | `runbook/runbook.yaml` | Tareas, dueños, dependencias, comando de cada tarea |
| Orquestación | `bitbucket-pipelines.yml` | Fases, paralelismo (AMA ‖ Phoenix) y gates manuales |
| Runner de tareas | `tools/run_tasks.py` | Ejecuta por fase/grupo, comprueba dependencias, audita en CSV |
| Validador | `tools/validate_runbook.py` | Se ejecuta en cada commit: IDs, dependencias, scripts, cobertura en el pipeline |
| Informe | `tools/report.py` | Genera horas reales y duraciones (sustituye a "Hora Inicio/Final Real") |
| Acciones Azure | `scripts/azure/*` | Traffic Manager, SQL MI FoG, Site Recovery (PowerShell), Batch, check DB |
| Acciones en servidores | `ansible/` | Data Guard switchover, jobs/sesiones Oracle, WebLogic, Forms |
| Infra DR | `terraform/dr-common/` | **Esqueleto**: Traffic Manager y FoG (importar antes de aplicar) |
| Parámetros | `config/` | `params.env`, `versions.yaml`, smoke tests, conectividad, secretos requeridos |

Terraform describe la infraestructura DR "siempre lista"; **no** ejecuta el failover. El failover lo hacen
los scripts y Ansible, orquestados por el pipeline.

## Modos de ejecución

`MODE` en los pipelines `dr-cutover` y `dr-rollback` (por defecto **dry-run**):

- `plan` (solo CLI local): imprime lo que haría.
- `dry-run`: ejecuta con `DRY_RUN=1`. Los comandos que modifican algo solo se muestran (`run` en `common.sh`),
  Ansible va con `--check`, y las lecturas (checks, smoke tests, validaciones de Data Guard) **sí** se ejecutan.
- `execute`: hace los cambios. Exige la variable de repositorio `DR_ALLOW_EXECUTE=yes`, que solo se pone el día del cutover.

Uso local: `python3 tools/run_tasks.py --phase dr --mode plan` y `python3 tools/validate_runbook.py`.

## Puesta en marcha

1. **Runner auto-alojado** (obligatorio). Bitbucket cloud no llega a las VMs privadas. Instalar un runner Linux con
   las etiquetas `self.hosted`, `linux`, `dr`, en la **región DR** y con conectividad a Oracle, WebLogic, Forms, SQL MI y Azure.
2. **Imagen toolbox**: construir `docker/Dockerfile` (no probado), publicarla en vuestro ACR y poner su nombre en `image:`.
3. **Identidad Azure** (elegir una):
   - `AZURE_USE_MSI=true` con identidad administrada en la VM del runner (recomendado, sin secretos), o
   - service principal: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_CLIENT_SECRET` (variable segura).
   - En ambos casos: `AZURE_SUBSCRIPTION_ID`. Permisos mínimos: Contributor sobre los RG de SQL MI, Traffic Manager, Batch,
     Site Recovery y Storage, y lectura de secretos en el Key Vault DR.
4. **Variables de repositorio**: `TEAMS_WEBHOOK_URL` (segura), `SQL_USER`, `SQL_PASSWORD` (seguras), `ANSIBLE_SSH_USER`,
   y una clave SSH configurada en Pipelines > SSH keys.
5. **Rellenar los `TODO`**: `config/params.env`, `ansible/inventory/hosts.yml`, `config/*.csv`, `config/required-secrets.txt`.
   Los scripts se niegan a ejecutarse mientras haya `TODO` en los parámetros que usan.
6. **Terraform**: importar los recursos existentes y comprobar que `terraform plan` sale sin cambios antes de usarlo.
7. Lanzar `preflight` y corregir todo lo que marque. Luego ensayar `dr-cutover` en `dry-run`.

## Flujo del pipeline `dr-cutover`

```
PRE preflight+prep → ✔ GO/NO-GO → DR notificar+monitorización → ✔ confirmar monitorización
 → ( AMA: BBDD, switchover, WebLogic  ‖  Phoenix: SQL MI, check DB, Site Recovery )
 → ✔ Forms compilado (KMM) + Phoenix desplegado (CAP)
 → ( AMA: startup + pods DRP  ‖  Phoenix: batch + verificación FoG )
 → ✔ pods DRP + wConfigurationV3
 → Batch AMA, Traffic Manager a DR, fin DR
 → ( smoke AMA ‖ smoke satélites ‖ smoke Phoenix )
 → pruebas de negocio → ✔ confirmar → ✔ GO definitivo (+ informe)
```

Si no hay GO: lanzar `dr-rollback`. Es un pipeline independiente, sin dependencias contra el cutover.

## Cambios respecto al Excel (revisar con el equipo)

- IDs renumerados (el Excel repetía el 3.3 cuatro veces) y dependencias explícitas. Son **más estrictas** que las originales:
  el Traffic Manager solo cambia cuando Batch, pods DRP y la verificación de FoG están hechos.
- "Check DB" usa `sys.databases` en lugar de `sysdatabases` (obsoleta). Cubre suspect, offline, emergency y sin acceso.
- Se añade un **preflight**, que no estaba en el runbook, para atacar los fallos del ensayo: conectividad a LDAP/Redis/BBDD,
  secretos que faltan en el Key Vault DR, estado del FoG y Data Guard.

## Puntos a validar (no he podido confirmarlos con el Excel)

1. **Etiquetas inconsistentes en el Excel**: "Check DB in San Jose" (DR) frente a "Check DB in West Europa" (rollback), y
   las instancias `sqlmi-phoenix-pro-001` (DR) frente a `sqlmi-phoenix-pro-001-neu` (rollback). Ajustar `SQLMI_*` en `params.env`.
2. **Site Recovery**: el script hace failover planificado pero **no Commit ni Re-protect**. El runbook no los describe y en el
   ensayo hubo un problema de "reprotect". Confirmar el procedimiento con DXC.
3. **Storage Account**: `az storage account failover` es disruptivo (queda LRS y se pierden datos sin replicar). Por eso
   `STORAGE_ACCOUNTS_FAILOVER` está vacío por defecto. **Key Vault**: el script solo comprueba que el DR es accesible;
   confirmar qué significa "Conmutación Key Vault" en el runbook.
4. **Oracle**: se asume Data Guard con `dgmgrl`. Los playbooks traen rutas, puertos y mecanismo de jobs de ejemplo (`TODO`).
5. **Azure Batch**: `BATCH_RESOURCE` (`job-schedule` o `job`) depende de cómo estén creados los de AMA y Phoenix.
6. **Zeus (KMM)**: sin API, sus tareas son manuales con gate. Si Zeus expone API, pasan a `type: auto` cambiando una línea del YAML.
7. **Monitorización Kyndryl** (parar/arrancar): manual, mismo caso.
8. **Post GO**: "Activar Batch AMA/Phoenix" es ambiguo en el Excel (cuenta DR o producción). Se deja manual.
9. **Smoke tests**: URLs de ejemplo. Los tests funcionales (crear asistencia, mapa, informes, MAIP 200) siguen siendo manuales;
   candidatos a Playwright en una segunda fase.

## Estado de la validación de este repositorio

Probado en local: validador (caso correcto y erróneo), runner (plan, dry-run, dependencias, gates manuales, confirmación,
bloqueo de `execute`, fallo de tarea) e informe. Sintaxis de bash y YAML correcta. Pipeline YAML parseado.
**No probado**: ejecución contra Azure, Oracle, Ansible, Terraform, PowerShell/ASR, la imagen Docker y el runner en Bitbucket
(no hay acceso a esos sistemas). Validar `bitbucket-pipelines.yml` con el validador de Bitbucket y ejecutar `shellcheck` en el primer push.
