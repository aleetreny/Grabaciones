# Procesador de llamadas

## Como usarlo

1. Copia los videos o audios nuevos en `01_Videos`.
2. Haz doble clic en el boton de tu sistema:
   - Windows: `INICIAR PROCESO - Windows.vbs`
   - Mac: `INICIAR PROCESO - macOS.command`
3. Si el equipo muestra algun aviso, aceptalo y espera.
4. Cuando termine, abre el archivo `.txt` que aparece en `03_Texto_para_Copilot`.
5. Sube ese archivo a Copilot.

## Importante

- La primera vez puede tardar bastante mas que las siguientes.
- No hace falta instalar nada a mano: el proceso intenta prepararlo todo solo.
- Cuando acaba, los videos procesados se mueven a `04_Videos_ya_procesados`.

## Carpetas que vas a usar

- `01_Videos`: aqui se ponen los videos o audios nuevos.
- `03_Texto_para_Copilot`: aqui aparece el archivo final que tienes que subir.

## Si quieres repetir el proceso

1. Mete nuevos videos o audios en `01_Videos`.
2. Vuelve a hacer doble clic en el boton de tu sistema.

## Preguntas frecuentes

### Quiero borrar transcripciones antiguas

Puedes borrar sin problema las carpetas con fecha dentro de `02_Transcripciones_por_llamada` y los archivos `.txt` de `03_Texto_para_Copilot`.

### Quiero volver a procesar un video ya usado

Mueve ese video desde `04_Videos_ya_procesados` de vuelta a `01_Videos` y vuelve a pulsar el boton.

### Quiero empezar de cero

Vacía el contenido de `02_Transcripciones_por_llamada`, `03_Texto_para_Copilot` y `04_Videos_ya_procesados`. Despues deja en `01_Videos` solo los archivos que quieras procesar.

### La primera vez tarda mucho

Es normal. La primera ejecucion puede tardar bastante mas porque el equipo se prepara solo.
