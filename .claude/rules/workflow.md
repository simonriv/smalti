# Workflow (Smalti)

- Ejecuta los planes de F2–F7 en modo nativo: implementa tú las tareas, sin un subagente implementador por tarea.
- Agrupa cada plan en bloques de 3–5 tareas y pide dos revisiones intermedias por fase a un revisor nuevo: una al terminar dominio y adaptadores, otra al terminar la app, cada una sobre el diff desde la anterior.
- Corrige los hallazgos de cada revisión intermedia (importantes y menores) en una sola tanda antes de seguir, cada uno con su prueba RED→GREEN.
- Cierra la fase con una revisión final de la rama (revisor nuevo, modelo más capaz) acotada a lo que cruza bloques (dominio y adaptadores con la app), a las tandas de correcciones posteriores a cada revisión intermedia y al cumplimiento de la spec en conjunto (criterios, enmiendas y anti-objetivos); pásale los hallazgos de las revisiones intermedias para que no los repita y no le pidas releer todo el diff.
- Tras la revisión final, haz una sola tanda de correcciones; luego mutación ≥ 80 % en SmaltiCore y suites en verde antes de los PR.
