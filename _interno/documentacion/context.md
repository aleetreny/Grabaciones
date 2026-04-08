Contexto del Proyecto — Pipeline de Transcripción y Análisis de Llamadas

1.  Objetivo del proyecto

Este repositorio implementa un pipeline end‑to‑end para:

*   Transcribir múltiples llamadas (audio/vídeo) usando Whisper en local.
*   Agregar todas las transcripciones de un día en un único archivo de texto.
*   Analizar ese archivo agregado usando Microsoft Copilot con un agente generalista, sin acceso a fuentes externas.

El foco NO es analizar llamadas individuales, sino extraer insights agregados:

*   motivos de llamada más frecuentes
*   incidencias recurrentes
*   patrones y tendencias
*   señales de frustración del cliente
*   recomendaciones operativas

Este caso de uso es típico de contact center / atención al cliente (por ejemplo, 50 llamadas al día).

***

2.  Decisiones de diseño clave (ya cerradas)

Arquitectura de análisis

*   NO se usa SharePoint, Teams ni OneDrive como knowledge source del agente.
*   El usuario sube manualmente un archivo .txt agregado al chat de Copilot.
*   El agente analiza solo el archivo adjunto en ese mensaje.

Tipo de agente Copilot

*   Agente generalista, sin knowledge sources configurados.
*   Opción “Only use specified sources” ACTIVADA.
*   Sin búsqueda web, sin org chart, sin contexto externo.

El agente actúa como un analista operativo de llamadas a partir de transcripciones agregadas.

***

3.  Flujo completo para el usuario final

Copiar todos los audios/vídeos del día en la carpeta videos/

Ejecutar un único binario:
    *   Windows: run\_transcription.exe
    *   macOS: run\_transcription

El pipeline transcribe cada llamada y agrega todas en un archivo diario

El usuario abre Copilot, selecciona el agente y sube el .txt diario

El usuario pregunta por el conjunto de llamadas (top problemas, conteos, tendencias, etc.)

El usuario final:

*   NO instala Python
*   NO instala FFmpeg
*   NO configura nada

***

4.  Estructura del repositorio (conceptual)

repo/

*   videos/                     (input: audios/vídeos del día)
*   transcriptions/
    *   daily/                    (output: archivo agregado diario)
    *   archive/                  (transcripciones individuales ya procesadas)
*   tools/
    *   ffmpeg/
        *   windows/ffmpeg.exe
        *   macos/ffmpeg
*   main.py                     (entrypoint único del pipeline)
*   transcribe\_whisper.py       (transcribe cada audio/vídeo)
*   aggregate\_transcripts.py    (agrega transcripciones del día)
*   bin/
    *   windows/run\_transcription.exe
    *   macos/run\_transcription
*   README.txt

***

5.  Transcripción (Whisper)

*   Se usa Whisper local (no API).
*   Cada audio/vídeo genera un .txt individual.
*   El idioma suele ser español (se puede forzar más adelante si se decide).
*   FFmpeg NO depende del sistema, se incluye en tools/ffmpeg.

Importante:  
El código ajusta el PATH en runtime para que Whisper use el FFmpeg incluido, no el del sistema.

***

6.  Agregación diaria de llamadas

Script: aggregate\_transcripts.py

Función:

*   Lee todos los .txt individuales
*   Crea un archivo diario con estructura clara por llamada

Formato lógico del archivo agregado:

LLAMADA 001  
Archivo original: call\_001.txt  
Contenido de la transcripción

LLAMADA 002  
Archivo original: call\_002.txt  
Contenido de la transcripción

El archivo final se guarda como:
transcriptions/daily/YYYY-MM-DD\_all\_calls.txt

Los .txt individuales se mueven a archive/ para evitar re‑agregaciones.

Este archivo agregado es el dataset que se analiza en Copilot.

***

7.  Empaquetado y distribución

Decisión clave:  
Los usuarios NO tienen Python, por lo que el pipeline se distribuye como binario.

*   Se usa PyInstaller
*   Un binario por sistema operativo:
    *   Windows: .exe
    *   macOS: binario nativo

No existe binario cross‑platform único (esto es normal y esperado).

***

8.  Rol del agente Copilot

El agente:

*   Trabaja exclusivamente con el archivo .txt subido por el usuario
*   Interpreta el contenido como conjunto de llamadas
*   Prioriza:
    *   frecuencia de incidencias
    *   patrones
    *   tendencias
    *   impacto en cliente
*   Responde con:
    *   resumen ejecutivo
    *   top problemas
    *   ejemplos textuales
    *   recomendaciones operativas

El agente NO:

*   busca información externa
*   usa conocimiento general
*   accede a repositorios o carpetas

***

9.  Estado actual del proyecto

*   Pipeline conceptual definido
*   Scripts de transcripción y agregación creados
*   Diseño del agente Copilot definido
*   Decisión de empaquetado Windows / macOS tomada

El siguiente paso técnico es terminar el empaquetado multiplataforma con PyInstaller y validar FFmpeg embebido.

***

10. Qué NO hay que replantear

*   Usar SharePoint / Teams como knowledge source
*   Pedir Python o FFmpeg al usuario
*   Analizar llamadas una a una en Copilot
*   Agente con acceso a “todo el tenant”

Estas decisiones están cerradas.

***

11. Qué sí puede venir después (fuera de scope inmediato)

*   Forzar idioma en Whisper
*   Añadir metadatos por llamada
*   Generar CSV resumen además del .txt
*   Firmar binarios
*   Centralizar ejecución en servidor

Nada de esto es necesario para el MVP actual.

***

Resumen corto (TL;DR)

Este repo convierte muchas llamadas diarias en un único archivo analizable y usa Copilot como analista, no como buscador de documentos.

El valor está en:  
agregación + lenguaje natural + cero fricción para el usuario final
