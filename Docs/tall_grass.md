# Hierba alta: pisadas y recorte delante de los pies

El mapa usa `Scripts/Overworld/overworld_environment_effects.gd`. La propiedad
`tall_grass_layer_path` apunta al TileMapLayer que contiene los tiles con el dato
personalizado booleano `is_tall_grass = true`.

Cuando los pies de un actor entran en una de esas celdas, aparece un único
`TallGrassFootOverlay` delante de su sprite. Usa
`Resources/Tileset/tall_grass_cut.png`: los 10 píxeles superiores transparentes
dejan ver el cuerpo y los 6 inferiores dibujan hierba delante de los pies.

El recorte se centra en la celda del terreno y hereda su transformación real:
16×16 píxeles, escalados a 20×20 en el mapa actual. No se escala según el tamaño
del personaje. Mientras el actor cruza una celda, el recorte permanece alineado
con ella; al cruzar a otra, se reutiliza el mismo sprite en la nueva celda.
Al salir de la hierba se oculta, y al eliminar al actor se elimina con él.

El recorte es hijo del sprite del actor, con el mismo Z y dibujado delante de
su padre. Por eso conserva el orden del actor respecto a árboles, casas y otras
capas del mapa. La animación de pisada continúa como hija del TileMapLayer de
hierba, y se activa al entrar o cambiar de celda para cada actor.

## Nuevos personajes y NPC, incluidos Pokémon

Los scripts actuales `OverworldPlayer` y `RandomWalkingNPC` ya incorporan el
grupo `grid_movement_actor`, por lo que sus nuevas instancias reciben ambos
efectos automáticamente, incluso si aparecen durante la partida.

Para un futuro NPC con un script distinto:

- Añadir su nodo de movimiento al grupo `grid_movement_actor`.
- Usar el origen de ese nodo como punto de apoyo de los pies sobre el suelo,
  igual que los personajes actuales.
- Colocar su imagen en un hijo `AnimatedSprite2D` o `Sprite2D`. Se busca primero
  el hijo llamado `AnimatedSprite2D`; si tiene otro nombre, se busca entre los
  descendientes y se usa el primer sprite encontrado.
- Incluir el actor dentro del mapa que contiene el controlador de efectos.

No requiere un identificador de diálogo ni un tamaño de imagen concreto.
`grass_foot_offset_y` conserva el punto de detección actual, 5 píxeles por encima
del apoyo de los pies. Esto permite detectar el interior del tile cuando el
personaje está exactamente sobre su borde inferior.

## Validación

`Tools/Overworld/validate_tall_grass_foreground.gd` comprueba entrada y salida,
los cuatro bordes de celda, alineación a 20×20, reutilización de un único sprite,
pisadas, personajes ocultos, NPC creados y eliminados durante la partida y un
actor genérico con `Sprite2D` para futuros NPC Pokémon. Se ejecuta con Godot en
modo `--headless --path . --script res://Tools/Overworld/validate_tall_grass_foreground.gd`.
