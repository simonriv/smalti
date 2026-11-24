# Testing (Smalti)

- No pidas ni planifiques pruebas físicas ni de uso real (teclado físico, días de uso, A/B a ciegas, retomar sesiones a mano) hasta que la app esté terminada: cada criterio de fase se cierra con pruebas automáticas (Swift Testing, XCUITest), mediciones o capturas; lo que solo pueda verificarse a mano se anota como aplazado en el checklist de la fase.
- Lanza XCUITest con una sola compilación por corrida: `scripts/test-ui.sh Clase1 Clase2/prueba …` compila una vez y corre todo lo pedido en un único `test-without-building`; no encadenes una invocación por clase.
- Tras cada corrección corre solo las pruebas de UI nuevas o cambiadas por ella; la regresión de las clases que toca el bloque se corre una vez al cerrar el bloque y otra al cerrar la fase.
- Comprueba el rojo en la capa más barata que reproduzca el fallo (dominio o adaptador); revierte y recompila la app para ver el rojo en XCUITest solo cuando la corrección es únicamente de la app.
- Durante la fase, muta solo los archivos de SmaltiCore que cambió la rama (`mutate.py --changed-since <base>`); la mutación completa (≥ 80 %) se corre una sola vez al cerrar la fase, cuando ya no cambia código del dominio.
- Corre siempre completas las suites unitarias de los paquetes tocados (son baratas).
