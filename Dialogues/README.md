# Sistema de diálogos de Belium

Esta carpeta contiene las fuentes narrativas editables. El runtime no consume
los JSON directamente: el compilador los valida y genera recursos Godot
comprimidos en `Resources/Dialogue/Compiled`.

La arquitectura está pensada para los tres capítulos y los cuatro personajes
jugables de Belium. Ningún ID de personaje ni capítulo está fijado en el
compilador: se descubren a partir de las fuentes.

## 1. Convención de archivos

```text
[dialogNumber]_[actorId]_[placeId].json
```

Ejemplos:

```text
0001_01Cynthia_leaftown.json
0001_Npc001OldManHarry_leaftown.json
```

Reglas:

- `dialogNumber` agrupa los archivos del mismo encuentro.
- `actorId` debe coincidir exactamente con `characterId` o `npcId`.
- `placeId` debe coincidir con el ID estable del área del mapa.
- Los IDs son claves técnicas estables; no deben depender del nombre visible.
- Por la convención actual, `actorId` no debe contener `_`. `placeId` sí puede
  contenerlos, por ejemplo `route_201`.
- Los diálogos de un lugar sólo se indexan y cargan al entrar en ese lugar.

Los objetos inanimados usan `[dialogNumber]_[object]_[placeId].json` y un
diccionario de textos simples. Su configuración se explica en la sección 14.

La carpeta contiene `.gdignore`, por lo que las fuentes legibles no se incluyen
en el PCK. Los `.res` compilados sí se incluyen. Esto dificulta la lectura casual
del guion, aunque no debe considerarse cifrado invulnerable.

## 2. Archivo de personaje jugable

El lugar ya está expresado en el nombre del archivo; no debe repetirse como un
objeto contenedor dentro del JSON.

```json
{
  "characterId": "01Cynthia",
  "characterName": "Cynthia",
  "dialogueColor": "#28839C",
  "Npc001OldManHarry": {
    "responseFirstDialogueEver": "...",
    "responses": {
      "I_Content001": "...",
      "I_Content003": "..."
    }
  }
}
```

- `responseFirstDialogueEver` es la respuesta al saludo irrepetible del NPC.
- `responses` relaciona el `dialogueId` dicho por el NPC con la respuesta del
  personaje controlado.
- Una respuesta es opcional. Si no existe, el NPC continúa o cierra según
  `closeDialogue`.
- `dialogueColor` controla el margen del panel cuando habla ese personaje.

El compilador todavía acepta la errata histórica
`reponseFirstDialogueEver`, pero toda fuente nueva debe usar
`responseFirstDialogueEver`.

## 3. Archivo de NPC

```text
dialogs
└── ChapterI / ChapterII / ChapterIII
    └── characterId
        ├── Story
        └── random
```

Cada capítulo puede contener diálogos diferentes para cada uno de los cuatro
personajes jugables. Que un NPC tenga Story para un personaje o capítulo no
implica que deba tenerla para los demás.

Las entradas de `Story` y `random` no llevan `characterId`: lo heredan del
bloque `dialogs.[chapterId].[characterId]` que las contiene.

Ejemplo de nodo lineal:

```json
{
  "dialogueId": "I_Content001",
  "dialogue": "...",
  "closeDialogue": false
}
```

Ejemplo de bifurcación:

```json
{
  "resumeCheckpoint": true,
  "dialogueId": "I_Content002",
  "dialogue": "...",
  "choices": [
    {
      "label": "Sí, por favor.",
      "nextDialogueId": "I_Content003"
    }
  ],
  "responses": {
    "I_Content003": {
      "dialogue": "...",
      "closeDialogue": false
    }
  }
}
```

Se admiten hasta cinco `choices`; la interfaz muestra tres y permite navegar
por las restantes.

## 4. Regla de intercambio 1 × 1

La conversación conserva turnos de una intervención por parte:

```text
NPC(dialogueId)
→ respuesta opcional del personaje al mismo dialogueId
→ siguiente intervención del NPC
```

Una elección cuenta como la respuesta del personaje. Por eso una bifurcación
se resuelve así:

```text
NPC I_Content002
→ choice del personaje
→ nextDialogueId = I_Content003
→ NPC responde con responses.I_Content003
→ personaje responde con responses.I_Content003 de su propio JSON
→ continúa el siguiente elemento de Story
```

Los `responses` de una bifurcación permanecen dentro del mismo objeto que
contiene sus `choices`; no se salta a otro elemento superior del array para
encontrarlos.

## 5. Primer contacto

El primer contacto se registra inmediatamente al presionar `F` o `Enter`, no al
finalizar el texto.

Secuencia:

```text
firstDialogueEver del NPC
→ responseFirstDialogueEver del personaje, si existe
→ primer nodo Story del capítulo actual
```

Todo ocurre en el mismo panel. El primer contacto se distingue por:

```text
área + personaje jugable + NPC
```

Por tanto, que Cynthia haya conocido a Harry no marca automáticamente que
Belium, Lucas o Maya también lo conozcan.

## 6. Story, checkpoint y cierre temporal

`resumeCheckpoint: true` declara el punto al que debe volver una Story que fue
interrumpida sin resultado terminal. Al alcanzarlo se guarda su `dialogueId` en
el pre-save como `checkpointDialogueId`.

Ejemplo actual:

- `I_Content004` cierra el panel sin definir `reward`.
- La próxima interacción vuelve directamente a `I_Content002`.
- No se recorren los nodos anteriores buscando dónde reanudar.

La antigua idea `repeatable` queda reemplazada por `resumeCheckpoint`, que
describe con precisión la función del nodo.

## 7. Significado de reward

`reward` es un **resultado narrativo persistente**, no necesariamente un objeto.
Puede representar una recompensa, ayuda futura, cambio del mundo, permiso,
alianza, información o cualquier condición que active eventos posteriores.

Es triestado:

| Estado | Significado |
|---|---|
| propiedad ausente | Story pendiente o reanudable |
| `reward: true` | resultado positivo terminal |
| `reward: false` | resultado negativo terminal o posibilidad perdida |

Cuando `reward` adquiere cualquier valor booleano:

- se elimina `checkpointDialogueId`;
- esa Story no vuelve a mostrarse en ese capítulo;
- las interacciones posteriores usan `random`;
- el resultado queda disponible para condiciones y eventos futuros.

El resultado pertenece a:

```text
área + personaje jugable + NPC + capítulo
```

Esto permite, por ejemplo, que una decisión de Cynthia en `ChapterI` active en
un capítulo posterior una ayuda para Lucas o Maya. El sistema que evalúa el
evento consulta explícitamente el resultado de Cynthia; no copia el resultado
al estado del otro personaje.

## 8. Diálogos random

Una vez resuelta la Story del capítulo (`reward` definido), se elige al azar una
entrada de `random`. Puede existir una respuesta del personaje con el mismo
`dialogueId`, pero no es obligatoria.

Los `dialogueId` de `random` deben ser únicos y no pueden reutilizar IDs de
Story. Se recomienda una convención explícita como `I_Random001`.

Si `random` está vacío, la interacción se consume sin abrir un panel vacío.

## 9. Estructura persistente

El progreso se guarda por área, personaje, NPC y capítulo:

```json
{
  "dialogue_progress": {
    "areas": {
      "leaftown": {
        "map_id": "map_001_leaftown_201_sandtown_202",
        "area_type": "town",
        "characters": {
          "01Cynthia": {
            "npcs": {
              "Npc001OldManHarry": {
                "interacted": true,
                "chapters": {
                  "ChapterI": {
                    "checkpointDialogueId": "I_Content002",
                    "reward": true
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
```

En datos reales no deben coexistir checkpoint y reward: al resolver la Story se
borra el checkpoint. La propiedad `reward` se omite por completo mientras el
resultado sea indefinido; no se guarda como `null` ni como `false` por defecto.

El save también mantiene `chapter_id` como ID técnico (`ChapterI`, `ChapterII`,
`ChapterIII`) separado de `chapter`, que puede ser un texto visible como
`Prólogo`.

## 10. Pre-save

Ruta actual:

```text
user://Saved/pre_save_slot_1.json
```

El pre-save es una copia de trabajo en disco del guardado real.

Se crea o actualiza cuando:

- el jugador da un paso después de guardar;
- cambia de área;
- inicia una interacción con un NPC;
- avanza un checkpoint o resuelve un resultado narrativo.

Contiene:

- área y mapa actuales;
- contactos con NPC por área y personaje;
- progreso Story por área, personaje, NPC y capítulo;
- el resto del estado que ya existía en el save.

La posición del jugador no se reescribe en cada paso. Se toma la posición viva
al usar la opción Guardar.

Durante la sesión, el pre-save es la fuente de lectura autoritativa. Al guardar:

1. se usa el pre-save como base;
2. se agregan posición, tiempo y demás datos vivos;
3. se reemplaza el save real de forma atómica;
4. se elimina el pre-save;
5. el siguiente paso o cambio de área crea una nueva copia de trabajo.

Al continuar una partida sólo se lee el save real. Por decisión actual, un
pre-save dejado por cerrar el juego se descarta; recuperar ese archivo quedará
para una futura opción de autosave.

## 11. Selección de conversación en runtime

Al interactuar, el UIRoot usa:

```text
área actual + npcId + characterId + chapter_id
```

Luego aplica este orden:

1. Sin contacto previo: `firstDialogueEver` y Story inmediata.
2. Contacto previo, `reward` ausente: Story desde `checkpointDialogueId` o desde
   su inicio.
3. `reward` presente (`true` o `false`): entrada aleatoria de `random`.

El NPC y el personaje se miran, el movimiento queda bloqueado y el diálogo no
puede cancelarse. Mantener `Z` o `Shift` sólo acelera la escritura.

El contenido de cada intervención se pagina en bloques de dos líneas. Al
terminar un bloque, el panel se detiene indefinidamente y requiere `Enter` o `F`
para iniciar las dos líneas siguientes. Si se confirma mientras una página aún
se está escribiendo, la primera pulsación completa esa página y otra pulsación
continúa; ni la velocidad normal ni el avance rápido cambian de página solos.

## 12. Compilación y validación

El plugin `Belium Dialogue Compiler` ejecuta la compilación automáticamente
antes de iniciar el proyecto desde el editor. Si un JSON es inválido, Godot
cancela la ejecución y muestra el error para evitar usar recursos desactualizados.

Compilar:

```powershell
Godot_v4.7.2-stable_mono_win64.exe --headless --path . --script res://Tools/Dialogue/compile_dialogue_sources.gd
```

El compilador valida, entre otras cosas:

- nombre de archivo e ID interno;
- pareja de NPC/personaje del mismo número y área;
- capítulos y personajes sin valores hardcodeados;
- `dialogueId` únicos dentro de Story;
- máximo de cinco choices;
- que cada `nextDialogueId` exista en el `responses` local;
- que cada entrada herede el personaje del bloque que la contiene.

Validación de regresión:

```powershell
Godot_v4.7.2-stable_mono_win64.exe --headless --path . --script res://Tools/Dialogue/validate_dialogue_system.gd
```

La validación comprueba el grafo compilado de Harry/Cynthia y la persistencia
independiente entre personajes y capítulos.

## 13. Extensión futura de StoryState

El sistema actual implementa el mínimo de la demo: contacto, checkpoint,
resultado narrativo e historial. Los efectos compilados están tipados para que
luego puedan ampliarse, sin introducir condiciones específicas dentro de los
mapas, hacia los dominios definidos en `Docs/Docs_Belium`:

- estado del mundo;
- estado de ruta;
- conocimiento del jugador;
- conocimiento de cada personaje;
- relaciones;
- eventos y batallas condicionadas;
- recuerdos del postgame.

Los mapas deben publicar triggers e IDs estables; la interpretación narrativa
pertenece a StoryState/EventRunner, no a scripts particulares del TileMap.

## 14. Carteles y otros objetos inanimados

Convención de archivo:

```text
[dialogNumber]_[object]_[placeId].json
0001_Carteles_Leaftown201SandTown202.json
```

El primer segmento es el número del archivo o colección. El segundo es un
nombre organizativo, como `Carteles`, `Estatuas` o `Avisos`; no lleva `_`.
El último segmento identifica el lugar o colección territorial. Puede llevar
`_` y debe respetarse exactamente, incluyendo mayúsculas.

Contenido:

```json
{
  "cartel_id": {
    "dialogueId": "id",
    "text": "..."
  },
  "cartel_id": {
    "dialogueId": "id",
    "text": "..."
  }
}
```

- La clave exterior (`cartel_id`) es el **Object Id** que se asigna en
  el mapa. No se introduce el `dialogueId` en ese campo.
- `dialogueId` identifica la intervención dentro del recurso compilado.
- `text` es el texto que se imprime, incluyendo saltos de línea `\n`.
- Tanto las claves de objetos como los `dialogueId` deben ser únicos entre los
  archivos del mismo `placeId`. Se aceptan letras sin acentos, números, `_` y
  `-` para esos identificadores.
- Cada entrada es independiente: leer el cartel de bienvenida no continúa con
  el cartel de consejos. Ambos pueden releerse cuantas veces se quiera.
- No hacen falta archivos de respuesta para los personajes, perfiles de NPC,
  capítulos, Story, random, rewards ni estado de primer contacto.

### Asignar los IDs desde Godot

Los dos carteles actuales ya están conectados. En el árbol del mapa, despliega:

```text
Mapa
  Piso
    fondo_casa
      Colisiones_fondo
        colision_cartel_leaftown
          Dialogue
        colision_cartel_001_201
          Dialogue
```

Selecciona el nodo **Dialogue**, hijo de cada colisión. En el Inspector verás:

| Nodo padre | Object Id | Dialogue Place Id |
|---|---|---|
| `colision_cartel_leaftown` | `welcome_leaftown` | `Leaftown201SandTown202` |
| `colision_cartel_001_201` | `tracks_trainers_201` | `Leaftown201SandTown202` |

Para añadir uno nuevo:

1. Agrega la entrada al JSON de su lugar con una clave y un `dialogueId` nuevos.
2. En **Sistema de archivos**, busca `Scenes/Overworld/dialogue_object.tscn` y
   arrástralo al árbol del mapa como hijo del objeto o de su `CollisionShape2D`.
   La escena añade un marcador de lectura; no añade imagen ni colisión física.
3. Selecciona la instancia y escribe la clave exterior en **Object Id**.
4. En **Dialogue Place Id**, escribe el sufijo del archivo. Con el ejemplo
   actual se escribe `Leaftown201SandTown202`, sin `0001_Carteles_` ni `.json`.
5. Coloca la cruz del marcador en el centro horizontal del borde inferior de
   la celda del objeto, sobre la misma línea de suelo que usan los pies. El
   jugador lo leerá desde la celda contigua. En los carteles actuales, los
   marcadores son hijos de la colisión y tienen desplazamiento Y de `9.5` y
   `8.5`, respectivamente, porque éstas están centradas en sus rectángulos.
6. Ejecuta el proyecto: el plugin compila los JSON automáticamente. Mira al
   objeto desde abajo y presiona **F o Enter**.

`Required Facing = (0, -1)` significa leer desde abajo mirando hacia arriba,
como los carteles actuales. Para una estatua u objeto legible desde cualquier
lado, usa `(0, 0)`. `Interaction Enabled` permite desactivar su lectura.
El nombre del nodo en el árbol es libre; el enlace depende de los campos del
Inspector, no de cómo hayas llamado al nodo.

Si **Dialogue Place Id** queda vacío, se usa la región actual (`leaftown`,
`route_201`, etc.). Esto sirve para archivos como `0002_Carteles_route_201.json`.
El archivo actual usa deliberadamente una colección común a varias zonas,
por eso ambas instancias especifican `Leaftown201SandTown202`. Esa colección
no renombra las regiones de cámara ni cambia el área del guardado. Sólo se
carga su índice cuando se interactúa con un objeto que la utiliza.

### Lectura y recursos compilados

El objeto abre el mismo panel inferior y bloquea el movimiento mientras se
lee. No muestra nombre de hablante ni opciones. Conserva la pausa obligatoria
cada dos líneas, `F`/`Enter` para avanzar, y `Z`/`Shift` para acelerar. La última
confirmación cierra el panel y devuelve el control. Estas lecturas no modifican
el progreso de NPC ni generan un pre-save por sí mismas.

El compilador produce un `.res` comprimido por objeto bajo
`Resources/Dialogue/Compiled/Objects/[placeId]` y entradas independientes en el
índice del lugar. Valida textos vacíos, IDs inválidos y duplicados antes de
escribir estos recursos. Los JSON de edición siguen excluidos por `.gdignore`.
Esto conserva el pipeline de recursos existente; compresión `.res` no equivale
por sí sola a cifrado PCK.

Prueba de integración:

```powershell
Godot_v4.7.2-stable_mono_win64.exe --headless --path . --script res://Tools/Dialogue/validate_object_dialogue.gd
```

## 15. Colores y citas dentro del texto

Estas marcas se aplican al texto visible de todos los JSON de diálogos:
carteles y otros objetos (`text`), NPC (`dialogue`, `firstDialogueEver`),
respuestas del personaje, elecciones (`label`) y nombres visibles de hablantes.

| Marca escrita en el JSON | Significado | Presentación |
|---|---|---|
| `_Pueblo Hojaverde_` | Pueblo, ciudad, ruta u otra locación | Rojo suave `#C45D67` |
| `*Cynthia*` | Personaje importante o NPC | Azul `#3578B8` |
| `'La luz recuerda los antiguos caminos.'` | Cita de poema, historia o mito | Cursiva |

Las marcas de apertura y cierre no se muestran en pantalla. Pueden encerrar
una palabra, varias palabras o una cita extensa, incluso con saltos de línea.
Se escriben alrededor de la expresión completa, sin espacios inmediatamente
después de abrir o antes de cerrar.

```json
{
  "welcome_leaftown": {
    "dialogueId": "00_welcome_leaftown",
    "text": "Bienvenido a _Pueblo Hojaverde_. *Harry* suele decir: 'La luz siempre encuentra el camino a casa.'"
  }
}
```

Se pueden combinar estilos, por ejemplo:

```json
{
  "text": "'En _Ruta 201_, *Cynthia* encontró el eco de una antigua promesa.'"
}
```

Toda la cita estará en cursiva; Ruta 201 además estará en rojo y Cynthia en
azul. Si una expresión combina las dos marcas de color, prevalece la más
interior. Cada marca necesita su pareja; una marca suelta se conserva literal.
Los apóstrofos dentro de palabras, como `d'Artagnan`, no abren ni cierran citas.

Para escribir los símbolos literalmente, anteponer una barra invertida. Como
JSON requiere escapar esa barra, en el archivo se escriben dos:

```json
{
  "text": "Estos símbolos son literales: \\_texto\\_, \\*texto\\*, \\'texto\\'."
}
```

Los IDs (`dialogueId`, `npcId`, `characterId`, claves de objetos, rutas y nombres
de archivo) nunca se interpretan como texto formateado. No hay que modificar
sus guiones bajos. El sistema tampoco interpreta BBCode escrito por el autor:
los corchetes de una frase se muestran literalmente.

### Presentación y paginación

`Scripts/Dialogue/dialogue_text_format.gd` interpreta las marcas al mostrar el
texto. El compilador sigue guardando las cadenas originales en los `.res`.
No es necesario duplicar diálogos ni introducir propiedades de estilo por
palabra. `DialoguePanel` expone `Location Text Color` y `Character Text Color`
en el Inspector para ajustar los dos colores globales de ese panel.

El panel utiliza `RichTextLabel` con la fuente Orbitron existente. Como el
proyecto sólo incluye Orbitron regular, la cursiva se obtiene mediante una
variación inclinada de esa misma fuente. Las líneas se miden con sus estilos
antes de dividirse en páginas de dos líneas. Los colores y la cursiva se
conservan al cambiar de página; la escritura gradual cuenta únicamente los
caracteres del texto visible, sin contar marcas ni etiquetas internas.

Las elecciones conservan sus botones, selección con ratón/teclado y scroll;
el texto enriquecido se dibuja dentro de cada botón. El índice de la elección
y los IDs que determinan el siguiente diálogo no cambian por el formato.

El **nombre del hablante en el encabezado** distingue su rol: los personajes
jugables, como Cynthia, usan turquesa `#28839C`; los NPC, como Harry, usan ocre
`#986030`. El rol se determina por el ID del personaje de la conversación, sin
depender del nombre visible. Los colores pueden ajustarse en el Inspector del
panel mediante `Playable Speaker Color` y `Npc Speaker Color`. En el encabezado
prevalece el color del rol aunque el nombre esté marcado con asteriscos; las
menciones `*nombre*` dentro del texto siguen usando el azul indicado arriba.

Los carteles y demás textos sin hablante aprovechan también el espacio del
encabezado oculto: sus una o dos líneas se centran verticalmente en el panel.
La alineación horizontal sigue a la izquierda. Al volver a un diálogo con NPC
o personaje, se restaura el espacio del nombre automáticamente.

Prueba de formato, paginación, escapes y elecciones:

```powershell
Godot_v4.7.2-stable_mono_win64.exe --headless --path . --script res://Tools/Dialogue/validate_dialogue_formatting.gd
```
