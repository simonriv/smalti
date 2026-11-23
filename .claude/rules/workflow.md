# Workflow (Smalti)

- Ejecuta los planes de F2–F7 en modo nativo: implementa tú las tareas, sin un subagente implementador por tarea.
- Agrupa cada plan en bloques de 3–5 tareas (dominio, adaptadores, UI) y, al cerrar cada bloque, pide una revisión a un revisor nuevo sobre el diff del bloque.
- Corrige los hallazgos importantes de un bloque antes de empezar el siguiente; corrige los menores en una sola tanda al final del bloque, cada uno con su prueba RED→GREEN.
- Cierra la fase con una revisión de la rama completa (revisor nuevo, modelo más capaz) y una sola tanda de correcciones; luego mutación ≥ 80 % en SmaltiCore y suites en verde antes de los PR.
