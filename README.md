# Dashboard OrbitalPM

Dashboard operativo HTML que combina el portafolio de Microsoft Loop con Azure DevOps mediante la sesión activa de Azure CLI.

## Uso

```powershell
cd C:\Users\WinterOS\Desktop\MiProyecto\DashboardOrbital
.\AbrirDashboard.ps1
```

El comando consulta Azure DevOps, actualiza `data.js` y abre el dashboard. Para abrir la última copia sin consultar nuevamente:

```powershell
.\AbrirDashboard.ps1 -SinActualizar
```

## Compartir con el equipo

Esta carpeta se puede compartir completa (por ejemplo, comprimida en ZIP) vía OneDrive, Teams o SharePoint. No contiene credenciales: la sesión de Azure se abre con la cuenta de quien la ejecuta.

Cada persona que la reciba debe:

1. Tener **Azure CLI** instalado (`InstallAzureCli.ps1` de referencia, o `winget install Microsoft.AzureCLI`).
2. Tener acceso de lectura a la organización `https://dev.azure.com/OrbitalPM/`.
3. Ejecutar una vez:
   ```powershell
   az login
   ```
4. Abrir el dashboard:
   ```powershell
   cd <carpeta descomprimida>
   .\AbrirDashboard.ps1
   ```

**Importante:** la tarea programada (`ProgramarActualizacion.ps1`) y el auto-refresco del navegador solo sincronizan datos en el equipo donde se registraron. Si alguien más quiere que su copia se actualice sola, debe ejecutar `.\ProgramarActualizacion.ps1` en su propia máquina después de copiar la carpeta.

## Modelo de datos

El archivo `portfolio.json` contiene una captura estructurada de **Orbital Engineering Project Portfolio**. Loop es la autoridad de vigencia:

- **Proyecto vigente:** aparece en el portafolio de Loop.
- **Proyecto completado:** tiene tareas activas en Azure DevOps, pero ya no aparece en Loop.
- **Tarea activa vinculada:** pertenece a un proyecto ADO mapeado a una fila vigente de Loop y no está en estado final.
- **Tarea semanal:** tarea, abierta o completada, cuyo `System.IterationPath` corresponde a una iteración con fechas que cruzan el periodo seleccionado.
- **Avance semanal:** tareas semanales en estado `Closed`, `Done` o `Completed` entre el total de tareas del sprint semanal.
- **Progreso Loop:** porcentaje administrativo reportado en el portafolio; no se sustituye por el avance del sprint.
- **Proyecto oculto:** fila de Loop en estado `Closing` o con 100% de progreso. No aparece en el portafolio vigente ni en las tarjetas de ingenieros; queda listado en la sección colapsable "Proyectos completados o cerrados".
- **Avance global de portafolio:** promedio del `Progreso Loop` entre los proyectos vigentes (no cerrados/100%). Es independiente del avance semanal basado en sprints de Azure DevOps.

La captura actual contiene 34 filas leídas de Loop el 15 de octubre de 2026. Cada fila conserva cliente, alcance, estado, progreso, ingenieros y los nombres de proyecto correspondientes en Azure DevOps. Los proyectos Loop todavía sin equivalencia ADO permanecen visibles con cero tareas vinculadas.

Cuando cambie el portafolio de Loop, debe actualizarse `portfolio.json` antes de ejecutar `ActualizarDatos.ps1`. El script valida el archivo y reporta:

- Proyectos vigentes de Loop.
- Mapeos que no existen en la organización de Azure DevOps.
- Proyectos ADO ausentes en Loop y, por tanto, considerados completados.
- Proyectos Loop que todavía no tienen mapeo ADO.

El periodo predeterminado es del 12 al 16 de octubre de 2026. Puede cambiarse al ejecutar:

```powershell
.\ActualizarDatos.ps1 -StartDate 2026-10-19 -EndDate 2026-10-23
```

Las fechas de sprint provienen de los nodos de clasificación de iteraciones de cada proyecto, no de `ChangedDate`. Los proyectos activos sin una iteración fechada para el periodo se mantienen en el inventario, pero no generan tareas semanales.

## Ingenieros considerados

El roster corresponde a las columnas de **Engineers/Projects Kanban Board**:

- Guillermo Portillo
- Marcela Ramirez
- Carla España
- Fernando Galdamez
- Oscar Lainez
- Mauricio Dávila
- Hugo Ortiz
- Manuel Galdamez
- Manuel Martinez

Los PMs, cuentas externas y Fabricio Quintanilla no se consultan. Las identidades se resuelven por los correos de Azure DevOps definidos en `ActualizarDatos.ps1`; por ejemplo, **Manuel Martinez** usa `manuel.martinez@esorbital.com`, aunque Azure DevOps muestre el nombre Maverick Martinez.

## Fuentes consultadas

- WIQL de Azure DevOps para tareas activas del roster.
- API de nodos de clasificación para fechas reales de iteración.
- WIQL por proyecto e iteración para obtener todas las tareas semanales, incluidas las completadas.
- API batch de work items para título, estado, responsable, proyecto e iteración.

## Actualización automática

El dashboard puede mantenerse sincronizado con Azure DevOps sin tener que ejecutar nada manualmente:

1. **Tarea programada de Windows** — ejecuta `ActualizarDatos.ps1` cada cierto tiempo para refrescar `data.js`:

   ```powershell
   .\ProgramarActualizacion.ps1              # cada 15 minutos (predeterminado)
   .\ProgramarActualizacion.ps1 -IntervalMinutes 10
   .\ProgramarActualizacion.ps1 -Remove      # para desactivarla
   ```

   Requiere que la sesión de `az` siga activa (`az login` si expira) y que el equipo esté encendido en el momento de la ejecución programada.

2. **Auto-refresco en el navegador** — con el dashboard abierto, revisa `data.js` cada 60 segundos. Si detecta un `generatedAt` más reciente, recarga la página sola. Se puede desactivar con el interruptor **"Auto-refresco"** junto al buscador.

### Qué sí y qué no se actualiza solo

- ✅ **Avance semanal**, tareas activas, tareas por sprint y conteos: se actualizan solos en cuanto `ActualizarDatos.ps1` vuelve a correr, porque provienen directamente de Azure DevOps.
- ⚠️ **Progreso Loop** y **Avance global de portafolio**: provienen del campo `Status`/`Progress` que el PM escribe a mano en la tabla de Microsoft Loop. Azure DevOps no tiene ninguna conexión automática hacia Loop, así que ese número solo cambia cuando:
  1. El PM actualiza el porcentaje en Loop, y
  2. Se vuelve a capturar esa fila en `portfolio.json` (hoy es un proceso manual; no hay una API pública de Loop para leerlo automáticamente).
