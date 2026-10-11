# Pokémon NPC: movimiento y gritos

## Starly ya configurado

La escena `starly_shiny_overworld.tscn` usa el script especializado `pokemon_walking_npc.gd`. Su instancia actual permanece en `Mapa/Casas/NPCs/Starly`, con la posición, escala y animaciones que ya tenía.

- Tiene un 70% de probabilidad de intentar un paso cada 0,8–1,8 segundos mientras está quieto. No es una probabilidad por fotograma.
- Conserva pasos de 20 px, colisiones, corrección suave de alineación y un radio de paseo de tres celdas por eje alrededor de su posición inicial.
- Camina a la misma velocidad base que Harry (40 px mundiales/segundo); se mueve con mayor frecuencia, no acelerando artificialmente su animación.
- Harry conserva sus valores: 10% cada 2,5–5,5 segundos.
- Al colocarte al lado de Starly, mirar hacia él y pulsar Enter o F, reproduce `starly.ogg` por `Map_Sound` al 60%.
- Durante el grito mira al jugador y deja de caminar; después retoma su paso pendiente o su paseo normal. Cynthia puede seguir moviéndose.
- Una pulsación frente al Pokémon no abre el menú ni un diálogo humano. Pulsar repetidamente durante el grito no lo reinicia ni lo superpone; cuando termina puedes volver a llamarlo.

## Cómo asignar el sonido a otro Pokémon

1. Abre la escena del Pokémon con doble clic en el panel **Sistema de archivos** de Godot. Para empezar puedes duplicar la escena de Starly con otro nombre y sustituir sus sprites.
2. Selecciona el **primer nodo de su árbol**, de tipo CharacterBody2D. Si duplicaste Starly, ese nodo se llama Starly: puedes renombrarlo al nuevo Pokémon.
3. Si no partiste de Starly, asígnale el script `pokemon_walking_npc.gd`, disponible en la carpeta `Scripts/NPC`.
4. En el Inspector busca la sección **Grito del Pokémon**. Si tienes muchos parámetros, escribe `cry` en el buscador del Inspector.
5. Arrastra el archivo `.ogg` del Pokémon desde el panel Sistema de archivos al campo **Cry Stream**.
6. Deja **Cry Bus** en `Map_Sound` y **Cry Volume Percent** en `60`. Este campo usa porcentajes de 0 a 100: no debes escribir `0.6`.
7. Guarda la escena y arrástrala al contenedor **NPCs** del mapa.

No necesitas añadir un AudioStreamPlayer manualmente: el script crea uno al ejecutar el juego. Tampoco necesita un JSON de diálogos ni un `Npc Id` para emitir su grito.

También puedes seleccionar una instancia concreta en el mapa y cambiarle **Cry Stream** desde su Inspector. Eso modifica solo esa instancia; editar la escena original cambia el valor compartido por sus instancias que no tengan una sobrescritura propia.

## Estructura requerida de la escena

El nodo principal debe ser CharacterBody2D y conservar dos hijos con estos nombres exactos:

- `AnimatedSprite2D`: con `idle_down`, `idle_up`, `idle_left`, `idle_right`, `walk_down`, `walk_up`, `walk_left` y `walk_right`.
- `CollisionShape2D`: el script adapta la huella de los pies a la cuadrícula, teniendo en cuenta la escala.

No copies la escala de Cynthia por obligación: cada Pokémon puede tener otro tamaño. Conserva su punto de apoyo en los pies; `Sprite Feet Offset` permite corregir un sprite que tenga mucho espacio transparente dentro de sus fotogramas. El Pokémon utiliza el mismo sistema existente de hierba alta que los demás actores.

## Ajustes de movimiento

| Campo del Inspector | Predeterminado Pokémon | Significado |
| --- | ---: | --- |
| Movement Probability | 0.70 | Probabilidad de intentar un paso en cada decisión. |
| Minimum Decision Delay | 0.8 | Espera mínima entre decisiones, en segundos. |
| Maximum Decision Delay | 1.8 | Espera máxima entre decisiones, en segundos. |
| Walking Speed | 40 | Velocidad del desplazamiento, en px mundiales/segundo. |
| Maximum Wander Distance Cells | 3 | Límite de paseo por eje alrededor de su hogar. |
| Initial Facing | down | Dirección inicial: down, up, left o right. |

Aunque tenga probabilidad alta, no atraviesa una pared ni sale de su radio para completar un paso. Si queda completamente encerrado, no se moverá. Para un Pokémon más tranquilo, baja su probabilidad o aumenta la espera; no hace falta modificar el script.

## Volumen y reproducción

El 60% corresponde al reproductor de ese Pokémon: no reduce todo el bus `Map_Sound` ni los sonidos de la interfaz. El volumen final sigue respetando cualquier ajuste global de ese bus y de Master. Godot permite ajustar ese nivel mediante su propiedad de volumen lineal. [Referencia de AudioStreamPlayer](https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer.html#class-audiostreamplayer-property-volume-linear).

Para gritos usa sonidos cortos y sin bucle. El script desactiva el bucle en una copia local para OGG, WAV y MP3, sin modificar el recurso importado compartido. Si falta el sonido o el bus indicado no existe, avisa en el depurador y consume la interacción para no abrir accidentalmente el menú.

## Comprobación rápida

Ejecuta el mapa, acércate a una celda de distancia, mira al Pokémon y prueba Enter y F. Comprueba que mira hacia ti, no camina durante el grito, no suenan dos copias al pulsar de nuevo y vuelve a pasear cuando termina. Alejándote o dándole la espalda, Enter/F conservan el comportamiento normal del menú si no hay otro interactuable enfrente.

La prueba automática `validate_pokemon_npc.gd`, en `Tools/Overworld`, verifica además colisiones, alineación y continuidad del diálogo de Harry. Usa rutas de prueba independientes: no modifica la partida real.

## Si no se reproduce el grito

Comprueba también la **instancia del Pokémon dentro del mapa**, no solo su escena original:

1. Selecciona `Starly` dentro de `NPCs` en el árbol del mapa.
2. En el Inspector, busca la propiedad **Script**. Debe usar `pokemon_walking_npc.gd`, heredado de su escena.
3. Si aparece `random_walking_npc.gd`, se ha sobrescrito el script con el de los NPC humanos. Usa la flecha de revertir esa propiedad para recuperar el script de la escena original; no borres el nodo ni sus demás ajustes.
4. Detén y vuelve a ejecutar el juego para cargar la configuración corregida.

Esa sobrescritura impedía el grito de Starly: el mapa sustituía el comportamiento Pokémon por el humano. Añadir un `Npc Id` no soluciona ese caso, pero puedes conservarlo como identificador opcional; no interfiere con el grito cuando está asignado el script correcto.
