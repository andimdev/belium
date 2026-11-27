# Pokémon: La parábola de Belium — instrucciones para agentes

Este repositorio contiene un fangame narrativo de Pokémon desarrollado en Godot. Antes de cambiar historia, arquitectura o datos, consulta `docs/00_INDEX.md` y el documento temático correspondiente.

## Principios no negociables

- El propósito narrativo es dar a Cyrus y Cynthia una historia de origen merecida.
- Belium y Cyrus son la misma persona. El interés no es ocultarlo, sino explicar su transformación gradual.
- El desenlace es fijo: Cyrus muere. Las rutas alteran perspectiva, conocimiento y contexto emocional, no el final.
- La muerte de Dragonair es el punto de ruptura, no una conversión instantánea en Cyrus.
- Darkrai sigue a Belium por decisión propia; no está capturado.
- Separar siempre verdad del mundo, conocimiento del jugador y conocimiento de cada personaje.
- La historia base documenta hechos e intención. No debe confundirse con el guion final ni con la implementación.

## Dirección técnica vigente

- Godot 4.x; conservar la versión exacta del proyecto como fuente de verdad.
- Presentación 2.5D: personajes/NPC 2D; mapas, combates y cinemáticas 3D.
- Modelos Pokémon mediante Blender → GLB → Godot; el coste real depende de mallas, materiales, texturas, animaciones y carga simultánea, no del número bruto de archivos GLB.
- Sistemas modulares y dirigidos por datos. No codificar progreso narrativo dentro de mapas individuales.
- Estado narrativo centralizado: `world_state`, `player_knowledge`, `character_knowledge`, relaciones y rutas vistas.
- Preservar cambios existentes y verificar antes de reemplazar recursos.

## Convenciones documentales

- Español para diseño y canon.
- Marcar contenido no confirmado como `[POR DEFINIR]`; no convertir propuestas antiguas en canon.
- Si código y documentación discrepan, registrar la discrepancia antes de decidir cuál corregir.
- Las cifras de balance son provisionales salvo indicación expresa.
- Mantener `docs/02_TIMELINE.md` como referencia cronológica y `docs/01_NARRATIVE_CANON.md` como autoridad narrativa.

## Propiedad intelectual y distribución

Proyecto fan no oficial. No afirmar afiliación con Nintendo, Game Freak o The Pokémon Company. Mantener un registro de procedencia/licencia de cada recurso y evitar redistribuir material extraído sin autorización. La distribución pública y la monetización requieren revisión legal específica.
