# Regiones de cámara: Pueblo Arena como ejemplo

## Qué se configura y dónde

Abre `Maps/map_001_leaftown_201_sandtown_202.tscn`. En el árbol de la escena,
despliega el primer nodo (el nombre largo del mapa), después `CameraZones` y
selecciona `SandTown`. Los parámetros del script aparecen en el Inspector.

**Hay dos rectángulos diferentes**:

- `SandTown/RegionShape`: dónde deben estar los pies del personaje para considerar
  que entró al pueblo. Se edita seleccionando ese hijo y sus tiradores en la vista 2D.
- `SandTown > Camera Bounds`: hasta dónde puede mirar la cámara en esa región.
  Puede incluir árboles de borde y un poco de la región vecina. No cambia las
  colisiones ni el lugar donde aparece el aviso «Pueblo Arena».

El Area2D y CameraZones conservan posición `(0, 0)` y escala `(1, 1)`.
Así las coordenadas siguientes coinciden con las del mapa. No copies el escalado
1.25 de los tiles a CameraZones: las celdas del mundo ya miden 20px.

## Configuración actual

| Selección / propiedad | Valor | Significado |
| --- | --- | --- |
| SandTown / Zone Id | `sand_town` | Identificador estable. |
| SandTown / Display Name | `Pueblo Arena` | Nombre que muestra la interfaz. |
| SandTown / Camera Bounds / Position | X `1420`, Y `-780` | Esquina superior izquierda del encuadre permitido, antes de ocultar filas. |
| SandTown / Camera Bounds / Size | X `1200`, Y `1060` | Ancho y alto, **no** coordenadas de la esquina inferior derecha. |
| SandTown / Hidden Boundary Rows | X `0`, Y `5`, Z `5`, W `5` | Filas ocultas: izquierda, arriba, derecha, abajo. |
| SandTown / Transition Duration | `2` | Cambio gradual de cámara en segundos. |
| SandTown / Priority | `10` | Si dos zonas se superponen, gana la de mayor prioridad. Evitar empates en zonas superpuestas. |
| RegionShape / Transform / Position | X `2070`, Y `-414` | Centro del rectángulo de detección que dibujaste. Se conservó. |
| RegionShape / Shape / Size | X `1100`, Y `732` | Ancho y alto de la detección. Se conservó. |

`Camera Bounds` abarca desde `(1420, -780)` hasta `(2620, 280)`. Las cinco filas
excluidas equivalen a 100px por lado. El límite final queda desde `(1420, -680)`
hasta `(2520, 180)`. El mapa tiene terreno dibujado en todo ese rectángulo.

El límite izquierdo incluye 100px de la Ruta 201 para dar margen a la entrada.
Allí no se ocultan filas porque hay una conexión, no un borde exterior. Por la
misma razón, Ruta 201 ahora tiene `Hidden Boundary Rows / Z = 0`: su salida hacia
Pueblo Arena no debe quedar detrás del límite de cámara.

Se mantiene el acercamiento global del 15% (`Camera Zoom Multiplier = 1.15` en el
nodo principal del mapa). No hace falta calcular un zoom distinto en cada área:
se adapta al rectángulo y a la proporción de la ventana para no mostrar el vacío.

## Cómo configurar otra zona

1. Dentro de `CameraZones`, duplica una región configurada. Ponle un `Zone Id` único
   y el nombre visible. Si duplicaste el Shape, usa **Hacer único / Make Unique**
   antes de cambiar su tamaño para no redimensionar también la zona original.
2. Selecciona su hijo `RegionShape` y dibuja dónde empieza y termina esa región.
   En un rectángulo, Position es el **centro** y Shape / Size su tamaño.
3. Selecciona el Area2D padre. En `Camera Bounds`, Position es la **esquina
   superior izquierda**, no el centro. Size es el ancho y alto del terreno que
   puede verse. No lo dejes en ceros.
4. Si quieres empezar usando las mismas dimensiones de un RegionShape rectangular
   sin rotación ni escalado: `Position = centro − tamaño / 2`, y `Size = tamaño`.
   Después amplía el encuadre si hace falta mostrar más entorno. Para el RegionShape
   actual de Arena, esta cuenta da Position `(1520, -780)`, Size `(1100, 732)`;
   el encuadre configurado es más amplio a propósito.
5. En `Hidden Boundary Rows`, usa 5 donde el borde tenga ocho **celdas** de
   profundidad y quieras ocultar las cinco externas. Usa 0 en las conexiones.
   Los recortes combinados nunca deben consumir todo el ancho o el alto.
6. Prueba entrando desde cada acceso y acercándote a los extremos. Conserva 2s
   de transición o aumenta el tiempo si quieres un cambio más lento.

Estas regiones no necesitan colisión física: Collision Layer y Mask quedan en 0,
y Monitoring/Monitorable desactivados. El mapa comprueba la posición directamente.

La parte sur que queda fuera de tu RegionShape de Arena sigue fuera de esta región.
Cuando diseñes la siguiente ruta, agrega su propia zona o amplía la actual según
dónde quieras que cambie el nombre y el encuadre.

## Aviso de escena grande al guardar

Era una advertencia de tamaño, no un fallo del guardado. Se extrajeron ocho
TileSets a recursos binarios comprimidos en `Resources/Tileset/Map001/`.
La escena conserva su nombre, su UID y el formato `.tscn`; sigue siendo editable
normalmente. Las celdas pintadas, colisiones, fuentes y datos `is_tall_grass` de
los recursos convertidos se conservaron y se verificaron tras volver a cargarlos.

El TileSet de `Mapa/Arbol_fondo/arbol_2` sigue incrustado. Su fuente 1 apunta a
`utils_2_.png` (192×112). Tras confirmar que la imagen fue recortada en Aseprite,
se eliminaron únicamente sus 1631 definiciones fuera del tamaño actual. Se
conservaron las 73 definiciones válidas de esa fuente y todas las celdas pintadas
del mapa: ninguna dependía de los tiles eliminados. Las otras dos fuentes que
utilizan esa misma imagen también se verificaron, sin requerir cambios.

La copia previa a esta limpieza está en
`.godot/map_before_utils2_cleanup_20261009.tscn.backup`; es un respaldo local
temporal que se perderá si se borra la carpeta `.godot`.

Editar el dibujo en Aseprite no invalida por sí solo un TileSet. Reducir el lienzo
puede dejar coordenadas fuera de la imagen; mover los dibujos dentro del lienzo
puede cambiar lo que representa cada tile, aunque sus coordenadas sigan siendo
válidas. Para conservar un mapa existente, mantén el tamaño y la posición de los
tiles cuando sea posible. Después de recortar, revisa las fuentes afectadas y
las celdas que las utilizan. `Tools/Overworld/validate_tileset_bounds.gd` verifica
los límites y las referencias del mapa sin ejecutar la partida ni modificarlo.

Al seguir ampliando el mapa, los datos de celdas también crecerán y el aviso puede
volver. En ese momento se puede separar el mapa en escenas de sectores, o evaluar
`.scn` para escenas particularmente grandes. No se desactivó la advertencia.
