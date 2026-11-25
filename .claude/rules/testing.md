# Testing (Smalti)

- No pidas ni planifiques pruebas físicas ni de uso real (teclado físico, días de uso, A/B a ciegas, retomar sesiones a mano) hasta que la app esté terminada: cada criterio de fase se cierra con pruebas automáticas (Swift Testing, XCUITest), mediciones o capturas; lo que solo pueda verificarse a mano se anota como aplazado en el checklist de la fase.
- Lanza XCUITest con una sola compilación por corrida: `scripts/test-ui.sh Clase1 Clase2/prueba …` compila una vez y corre todo lo pedido en un único `test-without-building`; no encadenes una invocación por clase.
- Tras cada tanda de correcciones corre solo las pruebas de UI nuevas o cambiadas por ella; la regresión de las clases tocadas se corre una vez en cada revisión intermedia y otra al cerrar la fase.
- Comprueba el rojo en la capa más barata que reproduzca el fallo (dominio o adaptador); cuando la corrección es solo de la app, revierte y recompila para verlo en XCUITest, con todas las de la tanda en una sola corrida.
- Durante la fase, muta una sola vez por revisión intermedia, después de sus correcciones, solo los archivos de SmaltiCore que cambió la rama (`mutate.py --changed-since <base>`); mata cada sobreviviente con una prueba nueva verificada aplicando el mutante a mano, sin repetir la corrida. Al cerrar la fase, muta una sola vez (≥ 80 %) solo los archivos de SmaltiCore que cambió la fase (`--changed-since origin/develop`); nunca corras la mutación completa de SmaltiCore, aunque la rama toque código compartido.
- Corre las mediciones (latencias, GPU, capturas a demanda) solo al cerrar la fase.
- Corre siempre completas las suites unitarias de los paquetes tocados (son baratas).
