# Guía de capas del mapa: revisión y crecimiento

Revisión: 9 de octubre de 2026. Mapa: `map_001_leaftown_201_sandtown_202`.

## Conclusión

La base es aprovechable para la demo. No recomiendo rehacer el mapa ni abandonar los TileMaps. Sí conviene unificar las reglas de profundidad antes de colocar cientos de edificios: ahora algunas piezas se dibujan siempre encima del personaje y otras dependen de su posición vertical.

Mi recomendación es **TileMaps para terreno y elementos repetitivos; escenas reutilizables para edificios y objetos complejos; actores y objetos altos compartiendo una misma ordenación por su base**. No una capa nueva por casa.

Este documento es una revisión y un plan, no una reestructuración aplicada. Se retiró la implementación reciente que separaba las sombras de las fachadas, sus materiales, su comprobación y su guía anterior. Se conservaron las capas y ajustes del usuario. Las futuras sombras estáticas por casa quedan pendientes para esta demo, sin calcular el origen de una luz.

## 1. Qué tomamos realmente de Pokémon Platino

Platino no ofrece una receta literal de capas 2D trasladable a Godot. La investigación comunitaria documenta modelos del escenario, objetos colocados por identificador y transformación, atributos de terreno separados para colisión/comportamiento y una matriz de segmentos de mapa. Es una referencia útil de organización, no un motivo para convertir Belium a 3D. [Formato de mapas de pret/pokeplatinum](https://github.com/pret/pokeplatinum/blob/main/docs/maps/file_format_specifications.md).

La fuente es una descompilación comunitaria en desarrollo, no un manual oficial de Nintendo. [Presentación del proyecto](https://github.com/pret/pokeplatinum/blob/main/README.md).

La adaptación que propongo para Belium es propia: reutilizar edificios completos, distinguir apariencia de colisión y organizar el mundo por zonas. El objetivo visual es que el personaje pase delante o detrás de un objeto con coherencia, sin que una fila de su tejado corte arbitrariamente su cabeza.

## 2. Tres conceptos que no deben confundirse

- **Z Index:** prioridad de dibujo. Un nivel superior no se vuelve inferior porque el personaje camine hacia abajo. Con `Z As Relative` activado se suma el Z de los padres.
- **Y Sort:** compara posiciones verticales entre elementos del mismo Z efectivo. Los contenedores intermedios deben permitir esa ordenación; uno sin Y-sort puede agrupar sus hijos como una sola unidad. El punto de comparación debe representar el apoyo del objeto, no su parte superior.
- **Colisión:** determina dónde se puede caminar. Cambiar Z no mueve ni corrige una pared física.

Las dos primeras reglas están descritas en [CanvasItem de Godot](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html#class-canvasitem-property-y-sort-enabled). No uses el orden visual de la lista de nodos como única garantía de profundidad.

## 3. Inventario de las capas actuales

Z indica el valor acumulado de los nodos del mapa, no necesariamente el valor local mostrado en el Inspector. Un tile también puede añadir ajustes propios. Se revisaron las tres capas de casas: sus celdas inspeccionadas no añaden Z por tile.

`Mapa`, `Casas` y `Arbol_fondo` tienen Y-sort activado. El mapa contiene 14 nodos TileMapLayer, incluyendo el contenedor `NPCs` y la guía de movimiento.

| Capa actual | Z | Y-sort de la capa | Evaluación / acción aconsejada |
| --- | ---: | --- | --- |
| `Piso/piso_abajo` | -10 | No | Conservar como terreno base. |
| `Piso/piso_arriba` | -10 | No | Conservar para hierba y decoración baja. No mezclar aquí objetos que deban tapar personajes. |
| `Piso/fondo_casa` | -10 | No | Revisar su función: adecuado para elementos al ras del suelo, no para partes altas. Tiene una escala distinta al resto. |
| `Arbol_fondo/arbol_adicional` | 0 | Sí, origen 8 | Mantener si cada árbol tiene un apoyo coherente; revisar árboles formados por varias filas. |
| `Arbol_fondo/arbol_1` | 0 | Sí, origen 8 | Mismo criterio. Tiene un desplazamiento horizontal de aproximadamente -1 px mundial; comprobar que sea intencional. |
| `Arbol_fondo/arbol_2` | 0 | Sí, origen 8 | Mismo criterio; no asumir que el nombre “fondo” obliga a dibujarse detrás. |
| `Arbol_fondo/adicional_entornoArboreo_encima` | 0 | No | Elegir entre objeto ordenable por base o elemento superior fijo. Su estado actual no garantiza lo segundo. |
| `Casas/NPCs` | 0 | Sí | TileMapLayer vacío, sin TileSet, usado como contenedor. A futuro un Node2D con Y-sort sería más claro. |
| `Casas/casas` | 1 | Sí, origen 8 | Principal conflicto: se impone sobre actores en Z=0. Revisar por edificio, no bajar toda la capa a ciegas. |
| `Casas/detalles_casa` | 0 | Sí, origen 8 | Actualmente está en Z=0, no en Z=1. Sus detalles pueden separarse visualmente de la casa a la que pertenecen. |
| `Casas/colisionFrontal_casa` | 0 | Sí, origen 0 | Es una capa visual. Unificar su apoyo con el edificio; no contiene las colisiones físicas de las casas. |
| `Arbol_encima/capa_adicional1_encima` | 0 | No | El padre tampoco tiene Y-sort. Revisar su dibujo como bloque, no como árboles independientes. |
| `Arbol_encima/capa_adicional2_encima` | 0 | No | Mismo riesgo. “Encima” es solo un nombre, no una prioridad configurada. |
| `MovementGridGuide` | 4096 | No | Conservar como diagnóstico; no es terreno ni colisión. Ver advertencia de la sección 9. |

También influyen elementos que no son capas pintadas:

| Elemento | Estado actual | Recomendación |
| --- | --- | --- |
| Cynthia y Harry | Z=0, ordenación desde los pies | Conservar. No subirlos globalmente por encima de los árboles. |
| Partículas al pisar hierba | Heredan Z=-10 de la hierba | Conservar su relación con el suelo; evita que tapen los árboles. |
| Recorte de hierba en los pies | Hijo del sprite del actor | Conservar: acompaña al personaje sin cubrir globalmente otros objetos. |
| Animación del estanque | `PondWaterEffect`, Z=8 | Revisar antes de añadir puentes o Surf: hoy puede quedar encima de actores y edificios si se superponen. |
| Nubes y viento | CanvasLayer 5 | Separación apropiada para el cielo; no mezclar con las capas del suelo. |
| Interfaces | `UIRoot`, CanvasLayer 100 | Conservar independiente del mundo y por encima del clima. |

Los números de CanvasLayer y Z Index pertenecen a ordenaciones distintas. La guía con Z=4096 no pasa por eso por encima de la interfaz de otro CanvasLayer.

## 4. Qué corregir primero

### A. Un edificio no debería tener varias reglas incompatibles de profundidad

La casa en Z=1, sus detalles en Z=0 y la fachada en Z=0 explican por qué Cynthia puede estar delante de una parte y detrás de otra. No es un problema que se resuelva haciendo más grande la colisión del personaje.

Además, `casas` y `detalles_casa` tienen origen Y=8, mientras la fachada tiene origen Y=0. Con escala 1,25, esa diferencia representa 10 px mundiales. Es una inconsistencia que conviene revisar, **pero poner 8 en todas las capas no basta**: una casa pintada con muchas celdas sigue teniendo múltiples puntos de ordenación.

Tampoco basta guardar un conjunto de tiles como patrón: facilita pintar, pero no convierte todas sus filas en un único objeto visual.

Para una casa normal, prefiero un único apoyo en su base frontal, con fachada, ventanas y tejado dibujados como una unidad. Al estar delante de esa base, el actor queda delante; al rodear el edificio por detrás, queda oculto cuando corresponde. En edificios grandes en L, pasajes o arcos pueden hacer falta secciones con apoyos diferentes: no hay un único pivote universal para cualquier arquitectura.

### B. Separar “árbol que rodeo” de “elemento que siempre está encima”

Un árbol normal debe compartir profundidad con el actor según la base del tronco. Una cubierta por la que realmente se pasa por debajo puede necesitar prioridad superior fija.

Actualmente `Arbol_encima` agrupa sus capas sin Y-sort en Z=0. Su origen participa en la ordenación del grupo; no se está evaluando la base de cada árbol. Esto merece pruebas tanto en Hojaverde como en Ruta 201 y Arena, incluyendo zonas con coordenadas Y negativas.

Para vegetación repetida, es razonable seguir usando TileMapLayer. La condición es configurar una base por árbol completo, por ejemplo mediante un tile que abarque su dibujo completo o ajustes coherentes de sus piezas. Si una especie tiene comportamiento complejo, una escena reutilizable puede ser más práctica.

### C. Dar a las colisiones un dueño claro

Las colisiones de las casas están en `Mapa/Piso/fondo_casa/Colisiones_fondo/colision_casa_1..4`, no en `colisionFrontal_casa`. Un nombre futuro como `Fachadas` describiría mejor esta última.

Hay también un polígono muy extenso, `Colision_arboles_1`, que recorre numerosos tramos del mapa. Bajo `Colisiones_arbol` se agrupan además estanque y barrera. No afirmo que esto produzca un problema de rendimiento hoy; sí será difícil mantenerlo al editar cientos de objetos.

Recomendación: cada edificio lleva su propia huella física; terreno y vegetación repetitiva usan colisiones de tiles o bloques manejables. Evitar bloquear el mismo espacio dos veces con una colisión del TileSet y otra manual. La silueta del techo no debe convertirse automáticamente en huella de suelo.

## 5. Organización propuesta para crecer

Este es un esquema conceptual, no un árbol ya implementado:

```text
Mapa
├── Terreno                    — suelo y decoración baja
├── MundoOrdenable             — Z=0, Y-sort activado
│   ├── Actores                — contenedor con Y-sort
│   │   ├── Jugador
│   │   └── NPCs
│   ├── Edificios              — contenedor con Y-sort
│   │   ├── Casa_001           — una unidad ordenable desde su base
│   │   └── Casa_002
│   └── VegetacionOrdenable    — árboles con base coherente
├── ElementosSuperiores        — solo aquello realmente cenital
├── Regiones                   — cámara, música, ubicación y clima local
├── MovementGridGuide          — diagnóstico existente
└── UIRoot                     — interfaz independiente
```

No hace falta que todos los objetos sean hermanos inmediatos. Los contenedores de organización deben mantener la ordenación compartida; el objeto individual puede conservar su dibujo como bloque. Cynthia no necesita pertenecer a `Casas` para verse correctamente: esa relación es visual, no de propiedad.

Una convención posible de niveles sería:

| Función | Z propuesto | Criterio |
| --- | ---: | --- |
| Terreno base | -30 | Césped, tierra, agua base. |
| Decoración baja y efectos de superficie | -20 | Caminos, marcas y reflejos que no deban cubrir cuerpos. |
| Sombras estáticas sobre suelo, futuras | -10 | Por debajo de los objetos sólidos. |
| Objetos ordenables | 0 | Actores, edificios y árboles; base coherente. |
| Elementos superiores reales | 10 | Cubiertas concretas; no todos los tejados. |

Los números son una propuesta, no una obligación ni valores de Platino. Se dejan espacios para categorías futuras. No cambies los Z actuales en bloque sin migrar y probar un objeto completo.

### Una escena por modelo de casa, no por cada tile

Prepararía una casa reutilizable que agrupe:

- Dibujo completo y variantes de fachada/tejado.
- Punto de apoyo identificado en su base.
- Huella física de paredes en el suelo.
- Puerta, interacción y punto de entrada/salida.
- Identificador propio de la instancia cuando la historia lo necesite.
- Sombra estática futura asociada a esa casa.

El dibujo puede seguir compuesto por tiles dentro de esa escena. No es obligatorio convertirlo a una imagen ni programar el edificio. Lo importante es que mover o duplicar la casa no deje detrás su colisión o su puerta.

Para una casa que deba ordenarse como bloque: contenedores `MundoOrdenable` y `Edificios` con Y-sort activado; raíz Node2D de cada casa con Z=0, Y-sort desactivado y origen en su base. Sus piezas visuales conservan el mismo Z efectivo y no se ordenan por filas. **Guardar como escena no basta** si se mantienen dentro los Z y la ordenación fragmentada actuales. Esta regla corresponde al dibujo sólido; la futura sombra de suelo tendrá su prioridad inferior propia.

Compartir recursos entre instancias; no duplicar el TileSet y las texturas para cada casa. Los ajustes únicos de un edificio, como su destino interior, sí deben pertenecer a esa instancia.

## 6. Sombras estáticas: decisión para esta demo

Queda acordado implementar después sombras fijas por edificio: forma, desplazamiento y transparencia definidos de antemano. No seguirán al sol ni calcularán el origen de la luz.

Dos resultados diferentes requieren atención:

1. **Sombra sobre el suelo:** una forma o textura bajo los personajes y demás objetos.
2. **Personaje que entra en esa sombra:** esa sombra inferior, por sí sola, no oscurece su pelo ni su cuerpo. Al implementar habrá que definir también cómo reciben la sombra los actores, respetando edificios y árboles interpuestos.

No propongo resolver el segundo punto con otra capa oscura global por encima de todo: volvería a introducir el problema que motivó esta revisión. Tampoco se reintrodujo ahora el sistema retirado.

Cuando preparemos esos recursos, habrá que evitar duplicar la sombra nueva con la que ya está pintada en el tileset. Conserva los originales hasta hacer esa migración. Las sombras estáticas evitan iluminación dinámica, pero siguen teniendo un pequeño coste de dibujo y superposición; no son gratuitas.

## 7. Cientos de edificios: rendimiento y mantenimiento

El número de capas no basta para medir rendimiento. Importan cuánto se dibuja, cuántos materiales y recursos se repiten, los efectos transparentes, la física y el procesamiento de los objetos.

- Conservar el terreno como TileMapLayer y sin Y-sort. Godot agrupa tiles para dibujarlos; las capas con Y-sort usan una agrupación diferente, por posición Y. No activar Y-sort indiscriminadamente. [Referencia de TileMapLayer](https://docs.godotengine.org/en/stable/classes/class_tilemaplayer.html#class-tilemaplayer-property-rendering-quadrant-size).
- Reutilizar TileSets externos. Es también la recomendación de Godot cuando distintas capas o mapas comparten tiles. [Uso de TileMaps](https://docs.godotengine.org/en/stable/tutorials/2d/using_tilemaps.html#specifying-the-tileset-in-the-tilemaplayer).
- Evitar una capa global nueva por cada edificio, un Z exclusivo por casa o un script que procese cada casa a cada fotograma sin necesidad.
- Mantener las escenas de modelos de edificios y sus recursos compartidos. Cientos de instancias no exigen cientos de copias de sus texturas.
- Organizar edición por pueblos/rutas o sectores antes de que el archivo resulte inmanejable. Dividir una escena mejora organización, pero no descarga automáticamente las zonas lejanas.
- Añadir carga/descarga por sectores solo cuando el tamaño o las mediciones lo justifiquen. Los bordes deben conservar profundidad y colisiones coherentes con el sector vecino.

La extracción anterior de recursos externos sigue siendo útil. Actualmente algunas capas vuelven a tener TileSets incrustados, entre ellas `detalles_casa` y `colisionFrontal_casa`; revisar su reutilización antes de multiplicar modelos. Un `.res` más compacto facilita almacenar recursos, pero no arregla por sí mismo la profundidad ni garantiza más FPS.

No he realizado una prueba de rendimiento con cientos de edificios. Estas recomendaciones reducen riesgo de mantenimiento y ordenación; no son una promesa de rendimiento medida.

## 8. Cómo revisar los parámetros en el editor

Para cada capa problemática:

1. Selecciona el nodo en el árbol de la escena.
2. En el Inspector, busca `Z Index`, `Z As Relative` y `Y Sort Enabled` dentro de las propiedades de ordenación de CanvasItem.
3. Revisa también sus padres: un Z heredado o un contenedor sin Y-sort puede cambiar el resultado.
4. Si es TileMapLayer, busca `Y Sort Origin`. Después revisa el origen y Z del tile en el editor del TileSet: son ajustes adicionales, no el mismo control.
5. Pregunta qué representa su apoyo: pies del actor, base del tronco o base de la casa. El borde de la imagen no siempre coincide con ese punto.
6. Prueba delante, detrás y a ambos lados. No decidas por una única captura de pantalla.

Para colisiones, activa la visualización de formas de colisión al ejecutar el juego y compara con los pies, no con el pelo. No cambies el Z para corregir un obstáculo físico ni el collider para corregir qué dibujo tapa a otro.

## 9. Precauciones antes de mover nodos

### Escalas y cuadrícula

Piso, casas y árboles usan escala 1,25: un tile de 16 px ocupa 20 px mundiales. Pero `fondo_casa` añade aproximadamente 0,8 y vuelve a escala mundial 1. Cynthia y Harry añaden otras escalas propias. No normalices todo a 1 ni arrastres actores entre padres escalados sin conservar posición y tamaño globales.

Las pequeñas diferencias como `0.9999998` suelen ser redondeo, no un error que deba corregirse masivamente. El desplazamiento de `arbol_1`, en cambio, merece revisión visual porque sí representa un píxel mundial.

### Referencias que hay que actualizar si se reorganiza

El mapa conserva rutas a jugador, hierba, suelo límite y regiones: `player_path`, `tall_grass_layer_path`, `camera_bounds_layer_path` y `camera_zones_root_path`. La guía de movimiento tiene otras referencias al jugador y al suelo. Varias pruebas existentes también buscan las rutas actuales de Cynthia, Harry y carteles.

Mover nodos sin actualizar esas referencias puede romper efectos, cámara o interacciones aunque el mapa se siga viendo bien. Conservar también los identificadores de mapa, área y NPC vinculados al guardado y diálogos.

### La guía blanca no es solamente dibujo

`MovementGridGuide` también configura la cuadrícula compartida de los actores. **No borres su script ni su nodo para ocultar las líneas.** En el estado revisado, `show_grid=false` oculta la visual y omite el recorrido que construye las celdas alcanzables, pero mantiene la configuración de los actores.

Para la demo final convendrá ocultarla con esa propiedad. Separar su inicialización de movimiento de su dibujo de diagnóstico sería una mejora futura; no se hizo en esta revisión.

## 10. Orden de trabajo recomendado

1. Conservar una copia del mapa actual. No empezar moviendo todas las capas.
2. Elegir una casa de Hojaverde como prueba y preparar su modelo reutilizable con base, dibujo y colisión propios.
3. Comprobar esa casa con Cynthia y Harry delante, detrás, por ambos lados y en la puerta. Revisar también encuentro con árboles y hierba.
4. Resolver el criterio de árboles: ordenables por base o cubiertas superiores, sin categorías ambiguas.
5. Aplicar el modelo aprobado al resto de casas de la demo. Actualizar referencias al mover actores o interacciones.
6. Implementar después las sombras estáticas acordadas y probarlas de día y de noche, incluyendo el oscurecimiento de actores si se mantiene ese requisito.
7. Antes de ampliar a cientos de edificios, medir carga, memoria y tiempo de fotograma; decidir entonces la división/carga de sectores.

### Lista de comprobación de cada edificio nuevo

- [ ] Tiene una base visual clara y alineada con la cuadrícula de 20 px.
- [ ] El personaje no pierde la cabeza al caminar delante.
- [ ] Al pasar detrás, no se dibuja encima del tejado.
- [ ] Los detalles no cambian de prioridad respecto de su fachada.
- [ ] Paredes y puerta coinciden con la huella del suelo.
- [ ] Se puede mover la instancia sin dejar colisiones o interacciones atrás.
- [ ] No añade recursos duplicados ni un Z exclusivo innecesario.
- [ ] Funciona con distintos tamaños de personaje y con NPCs.
- [ ] Su sombra futura no duplica la del tileset ni oscurece objetos indebidos.
- [ ] Sigue viéndose bien al cambiar de región, zoom y franja horaria.

**Prioridad práctica:** primero profundidad coherente y edificios reutilizables; después sombras estáticas; optimización adicional solo donde las mediciones la pidan.
