# Workflow (Smalti)

- Ejecuta los planes de F2–F7 en modo nativo: implementa tú las tareas, sin un subagente implementador por tarea.
- Agrupa cada plan en bloques de 3–5 tareas y pide dos revisiones intermedias por fase a un revisor nuevo: una al terminar dominio y adaptadores, otra al terminar la app, cada una sobre el diff desde la anterior.
- Corrige los hallazgos de cada revisión intermedia (importantes y menores) en una sola tanda antes de seguir, cada uno con su prueba RED→GREEN.
- Cierra la fase con una revisión de la rama completa (revisor nuevo, modelo más capaz) y una sola tanda de correcciones; luego mutación ≥ 80 % en SmaltiCore y suites en verde antes de los PR.
