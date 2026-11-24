import sys, pathlib
out = pathlib.Path(sys.argv[1])
HEAD = """<!doctype html><html lang="es"><head><meta charset="utf-8"><title>{title}</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap">
<style>
body{{margin:0;font-family:Inter,system-ui,sans-serif;color:#d7dae0;background:#0b0d12}}
.desk{{width:1440px;height:900px;position:relative;overflow:hidden;background-color:#0b0d12;background-image:radial-gradient(circle at 16% 20%,#284766 0,rgba(40,71,102,0) 38%),radial-gradient(circle at 84% 80%,#563663 0,rgba(86,54,99,0) 42%),radial-gradient(circle at 72% 12%,#1d5a55 0,rgba(29,90,85,0) 34%),radial-gradient(circle at 30% 92%,#5a4a2a 0,rgba(90,74,42,0) 30%)}}
.win{{position:absolute;border-radius:16px;border:1px solid rgba(255,255,255,0.09);box-shadow:0 30px 90px rgba(0,0,0,0.5);background:rgba(13,15,21,0.62);backdrop-filter:blur(28px) saturate(150%);display:flex;flex-direction:column;overflow:hidden}}
.strip{{height:40px;flex:none;border-bottom:1px solid rgba(255,255,255,0.05);display:flex;align-items:center;gap:8px;padding:0 14px;font-size:12.5px}}
.ws{{padding:5px 12px;border-radius:7px;color:#8b919c}} .ws.on{{background:rgba(122,162,247,0.13);border:1px solid rgba(122,162,247,0.5);color:#e6e9ef}}
.area{{flex:1;display:grid;gap:8px;padding:10px}}
.pane{{border-radius:11px;background:rgba(6,7,10,0.34);border:1px solid rgba(255,255,255,0.07);display:flex;flex-direction:column;overflow:hidden;position:relative}}
.pane.on{{border-color:rgba(122,162,247,0.5);box-shadow:0 0 0 3px rgba(122,162,247,0.13)}}
.ph{{height:30px;flex:none;display:flex;align-items:center;gap:8px;padding:0 12px;font-size:12px;border-bottom:1px solid rgba(255,255,255,0.05)}}
.dot{{width:7px;height:7px;border-radius:50%}}
.term{{padding:10px 14px;font:400 12.5px/1.62 'JetBrains Mono',monospace;color:#d7dae0;white-space:pre}}
.status{{height:28px;flex:none;border-top:1px solid rgba(255,255,255,0.05);display:flex;align-items:center;justify-content:space-between;padding:0 14px;font-size:11.5px;color:#8b919c}}
.kbd{{font-family:'JetBrains Mono',monospace;font-size:10.5px;padding:2px 6px;border-radius:5px;border:1px solid rgba(255,255,255,0.12);color:#aeb3bd;background:rgba(255,255,255,0.04);white-space:nowrap}}
.grp{{margin:0;padding:10px 12px 4px;font-size:10.5px;letter-spacing:.06em;text-transform:uppercase;color:#8b919c}}
.box{{position:absolute;border-radius:14px;border:1px solid rgba(255,255,255,0.12);background:rgba(20,22,30,0.82);backdrop-filter:blur(36px) saturate(160%);box-shadow:0 40px 100px rgba(0,0,0,0.55);overflow:hidden;display:flex;flex-direction:column}}
.field{{display:flex;align-items:center;gap:10px;height:52px;padding:0 16px;border-bottom:1px solid rgba(255,255,255,0.07);font-size:16px;color:#e6e9ef}}
.row{{display:flex;align-items:center;gap:12px;height:34px;padding:0 12px;border-radius:8px;font-size:13.5px}}
.row.sel{{background:rgba(122,162,247,0.13);color:#e6e9ef}}
.muted{{color:#8b919c}} .foot{{height:36px;display:flex;align-items:center;gap:16px;padding:0 16px;border-top:1px solid rgba(255,255,255,0.07);font-size:11.5px;color:#8b919c}}
.note{{position:absolute;font-size:12px;color:#8b919c;max-width:300px;line-height:1.5}}
.hl{{background:rgba(224,175,104,0.35);color:#e6e9ef;border-radius:2px}} .hl.cur{{background:#e0af68;color:#0b0d12}}
</style></head><body><div class="desk">{body}</div></body></html>"""
SEARCH_ICON='<svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="#8b919c" stroke-width="1.5"><circle cx="7" cy="7" r="4.5"/><path d="M10.5 10.5L14 14"/></svg>'

def window(left, top, w, h, ws, panes_html, cols, status_left, status_right="RAM 9.1 / 16 GB · GPU 9%", extra=""):
    tabs = "".join(f'<span class="ws{" on" if on else ""}">{n}</span>' for n, on in ws)
    return f'''<div class="win" style="left:{left}px;top:{top}px;width:{w}px;height:{h}px">
<div class="strip">{tabs}<span class="muted" style="font-size:16px">+</span><span style="flex:1"></span><span class="kbd">⌘K</span></div>
<div class="area" style="grid-template-columns:{cols}">{panes_html}</div>
<div class="status"><span>{status_left}</span><span>{status_right}</span></div>{extra}</div>'''

def pane(title, path, body, on=False, color="#6b717c", hollow=True, extra=""):
    dot = f'border:1.5px solid {color}' if hollow else f'background:{color}'
    return f'''<div class="pane{" on" if on else ""}"><div class="ph"><span class="dot" style="{dot}"></span><b style="font-weight:600;color:#e6e9ef">{title}</b><span class="muted">{path}</span></div><div class="term">{body}</div>{extra}</div>'''

# ---- help
sections = [
 ("Ventanas y workspaces", [("Nueva ventana","⌘N"),("Cerrar ventana","⇧⌘W"),("Pantalla completa","⌃⌘F"),("Nuevo workspace","⌃⌘N"),("Ir al workspace 1–9","⌃1…⌃9"),("Renombrar workspace…","en ⌘K")]),
 ("Paneles", [("Nuevo panel","⌘D"),("Cerrar panel","⌘W"),("Ir al panel 1–9","⌘1…⌘9"),("Enfocar panel hacia…","⌥⌘←↑↓→"),("Igualar paneles","⌃⌘=")]),
 ("Terminal", [("Copiar","⌘C"),("Pegar","⌘V"),("Seleccionar todo","⌘A"),("Limpiar pantalla","⌘L"),("Aumentar / reducir letra","⌘+ ⌘−"),("Prompt anterior / siguiente","⌘↑ ⌘↓")]),
 ("En el prompt", [("Completar","Tab"),("Aceptar sugerencia","→"),("Buscar en el historial","⌃R")]),
 ("Ratón", [("Abrir un enlace","⌘clic"),("Pegar la ruta de un archivo","arrastrar"),("Menú del terminal","clic derecho")]),
 ("Configuración y ayuda", [("Configuración…","⌘,"),("Reportar un problema o una idea…","en ⌘K"),("Mostrar registros…","en ⌘K")]),
]
def col(secs):
    h=""
    for name, rows in secs:
        h += f'<p class="grp">{name}</p>'
        for i,(t,k) in enumerate(rows):
            sel = " sel" if (name=="Paneles" and i==0) else ""
            kk = f'<span class="muted" style="font-size:11.5px">{k}</span>' if k.startswith("en ") or k in ("arrastrar","clic derecho") else f'<span class="kbd">{k}</span>'
            h += f'<div class="row{sel}"><span style="flex:1">{t}</span>{kk}</div>'
    return f'<div style="flex:1;display:flex;flex-direction:column;padding:2px 4px">{h}</div>'
bg = window(56,40,1328,820,[("solen",True),("billi",False)], pane("zsh","~/Projects/solen","% ",True)+pane("claude","~/Projects/solen","",False,"#e0af68",False),"1.35fr 1fr","solen · 2 paneles · dwindle")
help_box = f'''<div class="box" style="left:340px;top:100px;width:760px;height:640px">
<div class="field">{SEARCH_ICON}<span class="muted">Buscar atajos y acciones</span><span style="flex:1"></span><span class="kbd">esc</span></div>
<div style="display:flex;gap:8px;padding:4px 6px;flex:1;overflow:hidden">{col(sections[:3])}{col(sections[3:])}</div>
<div class="foot"><span>Ayuda de Smalti</span><span style="flex:1"></span><span><span class="kbd">↩</span> ejecutar</span><span><span class="kbd">esc</span> cerrar</span><span><span class="kbd">⌘,</span> configuración</span><span>Reportar un problema</span></div></div>'''
(out/"mockup-help.html").write_text(HEAD.format(title="Ayuda de Smalti",body=f'<div style="opacity:.55">{bg}</div>'+help_box))

# ---- menu
def menu(left, title_x, items):
    rows=""
    for it in items:
        if it=="—": rows+='<div style="height:1px;background:rgba(255,255,255,0.1);margin:5px 10px"></div>'; continue
        t,k = it if isinstance(it,tuple) else (it,"")
        arrow = "▸" if t.endswith("▸") else ""
        t = t.rstrip(" ▸")
        rows+=f'<div style="display:flex;align-items:center;height:22px;padding:0 12px 0 22px;font-size:13px;color:#e6e9ef"><span style="flex:1">{t}</span><span style="color:#8b919c;font-size:12.5px;margin-left:24px">{k}{arrow}</span></div>'
    return f'<div style="position:absolute;left:{left}px;top:24px;width:270px;padding:5px 0;border-radius:10px;background:rgba(40,42,50,0.92);backdrop-filter:blur(30px);border:1px solid rgba(255,255,255,0.12);box-shadow:0 18px 50px rgba(0,0,0,0.5)">{rows}</div>'
bar_titles=["Smalti","Archivo","Edición","Ver","Ventana","Ayuda"]
bar = '<div style="position:absolute;left:0;top:0;width:1440px;height:24px;background:rgba(30,32,38,0.7);backdrop-filter:blur(20px);display:flex;align-items:center;gap:20px;padding:0 16px;font-size:13px;color:#e6e9ef"><span style="font-size:15px"></span>' + "".join(f'<span style="{"font-weight:600;" if t=="Smalti" else ""}">{t}</span>' for t in bar_titles) + '</div>'
menus = [
 (20, [("Acerca de Smalti",""),"—",("Configuración…","⌘,"),("Recargar configuración",""),"—",("✓ Entrada de teclado segura",""),"—",("Servicios ▸",""),"—",("Ocultar Smalti","⌘H"),("Ocultar otros","⌥⌘H"),("Mostrar todo",""),"—",("Salir de Smalti","⌘Q")]),
 (300, [("Nueva ventana","⌘N"),("Nuevo panel","⌘D"),("Nuevo workspace","⌃⌘N"),"—",("Cerrar panel","⌘W"),("Cerrar workspace",""),("Cerrar ventana","⇧⌘W")]),
 (580, [("Copiar","⌘C"),("Pegar","⌘V"),("Seleccionar todo","⌘A"),"—",("Buscar…","⌘F"),("Buscar siguiente","⌘G"),("Buscar anterior","⇧⌘G"),"—",("Limpiar pantalla","⌘L"),("Buscar en el historial",""),"—",("Iniciar dictado…",""),("Emoji y símbolos","fn E")]),
 (860, [("Paleta de comandos","⌘K"),("Observatorio","⇧⌘A"),"—",("Layout ▸",""),("Igualar paneles","⌃⌘="),"—",("Aumentar letra","⌘+"),("Reducir letra","⌘−"),("Tamaño real","⌘0"),"—",("Desplazamiento ▸",""),"—",("Pantalla completa","⌃⌘F")]),
 (1140, [("Minimizar","⌘M"),("Zoom",""),"—",("Panel ▸",""),("Ir al agente que espera","⌘J"),"—",("Workspace ▸",""),"—",("Traer todo al frente",""),"—",("✓ solen",""),("billi","")]),
]
labels=["Smalti","Archivo","Edición","Ver","Ventana"]
mbody = f'<div style="opacity:.35">{window(56,60,1328,800,[("solen",True)],pane("zsh","~","% ",True),"1fr","solen · 1 panel · dwindle")}</div>' + bar
for (x,items),lab in zip(menus,labels):
    mbody += f'<div class="note" style="left:{x+2}px;top:{34+len(items)*22+20 if False else 400}px"></div>'
    mbody += menu(x,0,items).replace('top:24px',f'top:60px')
    mbody += f'<div style="position:absolute;left:{x}px;top:40px;font-size:11px;letter-spacing:.06em;text-transform:uppercase;color:#8b919c">{lab}</div>'
mbody += '<div style="position:absolute;left:20px;top:560px;width:270px;padding:5px 0;border-radius:10px;background:rgba(40,42,50,0.92);border:1px solid rgba(255,255,255,0.12)"><div style="margin:4px 10px 6px;padding:4px 8px;border-radius:6px;background:rgba(255,255,255,0.08);font-size:12px;color:#8b919c">Buscar</div><div style="display:flex;height:22px;align-items:center;padding:0 12px 0 22px;font-size:13px;color:#e6e9ef"><span style="flex:1">Ayuda de Smalti</span><span style="color:#8b919c">⇧⌘?</span></div><div style="height:1px;background:rgba(255,255,255,0.1);margin:5px 10px"></div><div style="height:22px;padding:0 22px;font-size:13px;color:#e6e9ef">Reportar un problema o una idea…</div><div style="height:22px;padding:0 22px;font-size:13px;color:#e6e9ef">Mostrar registros…</div></div><div style="position:absolute;left:20px;top:540px;font-size:11px;letter-spacing:.06em;text-transform:uppercase;color:#8b919c">Ayuda</div>'
mbody += '<div style="position:absolute;left:580px;top:560px;width:230px;padding:5px 0;border-radius:10px;background:rgba(40,42,50,0.92);border:1px solid rgba(255,255,255,0.12)">' + "".join(f'<div style="display:flex;height:22px;align-items:center;padding:0 12px 0 22px;font-size:13px;color:#e6e9ef"><span style="flex:1">{t}</span><span style="color:#8b919c">{k}</span></div>' if t!="—" else '<div style="height:1px;background:rgba(255,255,255,0.1);margin:5px 10px"></div>' for t,k in [("Copiar","⌘C"),("Pegar","⌘V"),("Seleccionar todo","⌘A"),("—",""),("Buscar…","⌘F"),("Limpiar pantalla","⌘L"),("—",""),("Nuevo panel","⌘D"),("Cerrar panel","⌘W")]) + '</div><div style="position:absolute;left:580px;top:540px;font-size:11px;letter-spacing:.06em;text-transform:uppercase;color:#8b919c">Menú contextual del terminal</div>'
mbody += '<div style="position:absolute;left:860px;top:560px;width:200px;padding:5px 0;border-radius:10px;background:rgba(40,42,50,0.92);border:1px solid rgba(255,255,255,0.12)"><div style="height:22px;padding:0 22px;font-size:13px;color:#e6e9ef;display:flex;align-items:center">Nueva ventana</div></div><div style="position:absolute;left:860px;top:540px;font-size:11px;letter-spacing:.06em;text-transform:uppercase;color:#8b919c">Dock</div>'
mbody += '<div class="note" style="left:1100px;top:560px">Los atajos salen del Keymap vigente: si se reasignan en el TOML, el menú cambia al recargar. Las entradas se desactivan con las mismas reglas que ⌘K.</div>'
(out/"mockup-menu.html").write_text(HEAD.format(title="Menú de Smalti",body=mbody))

# ---- search
term = 'npm run build\n> solen@1.4.0 build\n> next build\n\n  <span class="hl">warn</span>  - Using edge runtime on a page\n  ✓ Compiled successfully\n  <span class="hl cur">warn</span>  - Unused export in lib/date.ts\n  ✓ Linting and checking validity of types\n  <span class="hl">warn</span>  - Image without alt in app/page.tsx\n% '
sbar = '<div style="position:absolute;right:12px;top:40px;width:340px;height:36px;border-radius:9px;border:1px solid rgba(255,255,255,0.12);background:rgba(20,22,30,0.86);backdrop-filter:blur(30px);box-shadow:0 12px 30px rgba(0,0,0,0.45);display:flex;align-items:center;gap:8px;padding:0 8px 0 10px;font-size:13px">'+SEARCH_ICON+'<span style="flex:1;color:#e6e9ef">warn<span style="display:inline-block;width:1px;height:14px;background:#7aa2f7;vertical-align:-2px;margin-left:1px"></span></span><span class="muted" style="font-size:12px">2 de 3</span><span class="kbd">↑</span><span class="kbd">↓</span><span class="kbd">esc</span></div>'
sbody = window(56,40,1328,820,[("solen",True),("billi",False)], pane("npm","~/Projects/solen",term,True,"#9ece6a",False,sbar)+pane("zsh","~/Projects/solen","% git status\nOn branch develop\n% "),"1.35fr 1fr","solen · 2 paneles · dwindle")
sbody += '<div class="note" style="left:1060px;top:120px;max-width:300px">Barra de búsqueda: arriba a la derecha del panel enfocado. ↩ / ⌘G siguiente, ⇧↩ / ⇧⌘G anterior, esc cierra. Sin coincidencias: "Sin resultados".</div>'.replace('left:1060px','left:1080px').replace('top:120px','top:120px;display:none')
(out/"mockup-search.html").write_text(HEAD.format(title="Buscar en el panel",body=sbody))

# ---- feedback
fb = f'''<div class="box" style="left:460px;top:200px;width:520px">
<div style="padding:18px 20px 6px;font-size:15px;font-weight:600;color:#e6e9ef">Reportar un problema o una idea</div>
<div style="display:flex;gap:8px;padding:10px 20px">
<div style="flex:1;height:38px;border-radius:8px;background:rgba(122,162,247,0.13);border:1px solid rgba(122,162,247,0.5);display:flex;align-items:center;justify-content:center;gap:8px;font-size:13.5px;color:#e6e9ef"><span class="dot" style="background:#f7768e"></span>Fallo</div>
<div style="flex:1;height:38px;border-radius:8px;border:1px solid rgba(255,255,255,0.08);display:flex;align-items:center;justify-content:center;gap:8px;font-size:13.5px"><span class="dot" style="background:#bb9af7"></span>Idea</div></div>
<div style="display:flex;align-items:center;gap:10px;padding:10px 20px;font-size:13px"><span style="width:16px;height:16px;border-radius:4px;background:#7aa2f7;display:inline-flex;align-items:center;justify-content:center;color:#0b0d12;font-size:11px">✓</span>Guardar los registros de esta sesión para adjuntarlos</div>
<div style="padding:4px 20px 14px 46px;font-size:12px;color:#8b919c;line-height:1.5">Se guardan en Descargas y se muestran en Finder; los arrastras tú al issue.</div>
<div style="margin:0 20px 16px;padding:10px 12px;border-radius:8px;background:rgba(6,7,10,0.34);border:1px solid rgba(255,255,255,0.07);font:400 12px 'JetBrains Mono',monospace;color:#8b919c">Smalti 0.4.5 (abc1234) · macOS 27.2 · Apple M4</div>
<div class="foot"><span><span class="kbd">←</span> <span class="kbd">→</span> tipo</span><span><span class="kbd">espacio</span> registros</span><span style="flex:1"></span><span><span class="kbd">esc</span> cancelar</span><span style="color:#7aa2f7">Abrir en GitHub <span class="kbd">↩</span></span></div></div>'''
(out/"mockup-feedback.html").write_text(HEAD.format(title="Reportar un problema",body=f'<div style="opacity:.55">{bg}</div>'+fb))

# ---- windows (two windows + restore grouping)
w1 = window(40,60,640,500,[("solen",True),("billi",False)], pane("zsh","~/Projects/solen","% ",True)+pane("claude","~/Projects/solen","",False,"#9ece6a",False),"1.2fr 1fr","solen · 2 paneles · dwindle")
w2 = window(360,330,640,500,[("smalti",True)], pane("nvim","~/Projects/smalti","",True,"#6b717c")+pane("zsh","~/Projects/smalti","% swift test\n…",False,"#e0af68",False),"1fr 1fr","smalti · 2 paneles · columnas")
restore = '''<div class="box" style="left:1040px;top:60px;width:370px">
<div style="padding:14px 16px 4px;font-size:14px;font-weight:600;color:#e6e9ef">Retomar donde quedaste</div>
<p class="grp">Ventana 1 · 2 workspaces</p>
<div class="row" style="height:30px;font-size:13px"><span style="color:#7aa2f7">☑</span><span style="flex:1">solen <span class="muted">— zsh, claude</span></span></div>
<div class="row" style="height:30px;font-size:13px"><span style="color:#7aa2f7">☑</span><span style="flex:1">billi <span class="muted">— zsh</span></span></div>
<p class="grp">Ventana 2 · 1 workspace</p>
<div class="row" style="height:30px;font-size:13px"><span style="color:#7aa2f7">☑</span><span style="flex:1">smalti <span class="muted">— nvim, zsh</span></span></div>
<div class="foot"><span style="flex:1">Solo cambia la agrupación; el resto es Reanudar.dc.html</span></div></div>'''
notes = '<div class="note" style="left:1040px;top:330px;max-width:370px">⌘N abre otra ventana con un panel en el directorio del panel enfocado, en cascada. Cada ventana tiene sus workspaces y su ⌘1–9 / ⌃1–9. ⇧⌘W cierra solo la ventana al frente; la última ventana cerrada equivale a ⌘Q. ⌃⌘F: pantalla completa nativa, sin radio ni borde.</div>'
(out/"mockup-windows.html").write_text(HEAD.format(title="Varias ventanas",body=w1+w2+restore+notes))
