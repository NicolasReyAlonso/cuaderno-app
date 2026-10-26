# Contexto para el asistente: Cuaderno de definición

Eres el asistente de programación de Nico en este repositorio. Responde en español; el código, nombres de variables y commits en inglés. Antes de proponer cambios, lee los ficheros que vas a tocar. Haz cambios pequeños y verificables, y di qué comandos ejecutar para comprobarlos. En tareas grandes, hazlo por pasos y para a resumir después de cada uno.

## Qué es

App personal de gimnasio para una fase de definición: entrenos con sugerencias de progresión, planes por semanas, comidas, peso, datos de la pulsera y una guía. Viene de un cuaderno web en HTML; esta versión funciona en Android, iPhone, macOS y web, **también sin conexión**: guarda todo en el dispositivo y lo sincroniza con el servidor cuando está disponible. Por ahora la usa solo Nico; el objetivo a medio plazo es publicarla en Google Play.

## Stack

- `backend/`: Python 3.12, FastAPI 0.115, SQLAlchemy 2.0 (estilo `Mapped[...]`), PostgreSQL 16, Alembic, Pydantic v2 + pydantic-settings, JWT (PyJWT), contraseñas con argon2, python-multipart.
- `app/`: Flutter ≥ 3.27 / Dart ≥ 3.6 (el Mac de Nico tiene Flutter 3.47). Paquetes: flutter_riverpod 2.x, dio 5.x, flutter_secure_storage 9.x, image_picker, video_player, health 13.x, drift 2.x + drift_flutter (desarrollo: drift_dev, build_runner). **No añadas paquetes sin preguntar.**
- Servidor: Docker en el PC de Nico; el móvil llega por Tailscale con `http://` (por eso Android permite tráfico sin cifrar). Más adelante, Cloudflare Tunnel o un VPS con https.

## Estructura

```
backend/app/
  config.py        Settings con prefijo CUADERNO_ (DATABASE_URL, JWT_SECRET, CORS_ORIGINS, SEED_ON_STARTUP, MEDIA_DIR, MEDIA_URL_HOURS)
  db.py            engine, SessionLocal, Base con naming_convention (no la quites: Alembic la necesita)
  models.py        todas las tablas; al final importa sync/tracking (registra el gancho de sincronización)
  schemas.py       modelos Pydantic de entrada/salida; errores de validador con _invalid() (mensaje sin «Value error,»)
  security.py      hash, JWT, dependencias CurrentUser y DB
  seed.py          carga data/catalog.json (idempotente); DEFAULT_PROGRAM = "definicion-5d"
  services/        progression.py (doble progresión), body.py (media 7 días, grasa, ritmo), schedule.py (semana que toca),
                   media.py (tipo por bytes, límites, URL firmadas)
  sync/            tracking.py (anota cada cambio en sync_log), entities.py (qué se sincroniza y cómo: REGISTRY)
  routers/         auth, catalog (+ POST /exercises), programs, workouts (+ /today), media, body, nutrition,
                   health (/health/sync de la pulsera), importer, sync (/sync/pull, /sync/push, /sync/reference)
  data/catalog.json  61 ejercicios con figura, 81 alternativas, programa de 5 días, 90 alimentos
backend/alembic/versions/   0001 esquema · 0002 planes por semanas · 0003 fotos de ejercicios · 0004 datos de salud ·
                            0005-0007 sincronización · 0008 claves a ejercicios diferidas (borrar cuenta)
backend/tests/   pytest contra PostgreSQL real (conftest crea y borra las tablas); test_migrations compara modelos y migraciones

app/lib/
  core/api.dart        Dio con token, apiUrl por --dart-define=API_URL, apiMessage() para errores en español;
                       en macOS el token va al llavero clásico (el otro exige firmar la app)
  core/theme.dart      tema claro/oscuro, colores de los días, hintColors, paceStyle, Panel
  core/local/          local_db.dart (drift: Records, Outbox, Meta; esquema v2), sync_engine.dart (cola, envío, descarga,
                       conflictos), sync_api.dart, sync_controller.dart (proveedores y cuándo sincronizar),
                       sync_widgets.dart (icono de estado y pantalla de conflictos)
  features/home/       HomeShell: Entreno, Comidas, Peso, Salud, Guía (NavigationBar en móvil, NavigationRail desde 840 px)
  features/workout/    planner.dart (lógica de entreno sin servidor), workout_page, exercise_card, repositorio
  features/programs/   lista de planes, editor (semanas → días → huecos), PlanDraft
  features/nutrition/  diario, buscador, alimentos propios, editor de platos
  features/body/       Peso: registros, resumen calculado en el móvil, gráfica, punto de partida y objetivos
  features/health/     pulsera (health_reader: Health Connect/HealthKit), pestaña Salud (metrics, metric_chart)
  features/media/      fotos y vídeos de ejercicios propios (subir, ver, borrar)
  features/figures/    figure.dart (cinemática inversa, igual que la web) y figure_view.dart (animada y quieta)
  features/guide/      Guía (texto de Nico con sus números calculados)
app/test/          tests de lógica, de la base local y de pantallas; goldens/ con imágenes de las gráficas;
                   sync_live_test.dart prueba contra el servidor de verdad (solo con CUADERNO_LIVE)
app/web/           sqlite3.wasm (sqlite3 3.5.2) y drift_worker.js (drift 2.35.3): drift los necesita en web;
                   si se actualiza drift, hay que bajar las versiones que correspondan
datos/cuaderno_export.json   datos reales de Nico exportados del cuaderno web
```

Plataformas: Android con `MainActivity : FlutterFragmentActivity`, minSdk 26 y permisos de Health Connect solo de lectura; macOS con entitlements de red y de archivos elegidos por el usuario; iOS con los textos de cámara, fotos y Salud en Info.plist (falta activar HealthKit en Xcode).

## Comandos

```bash
docker compose up --build                       # db + api en :8000 (aplica migraciones y carga el catálogo), docs en /docs
cd backend && alembic revision --autogenerate -m "..."   # nueva migración: revísala a mano

# Tests del backend (base vacía cuaderno_test; créala una vez: docker compose exec db createdb -U cuaderno cuaderno_test)
cd backend && CUADERNO_DATABASE_URL=postgresql+psycopg://cuaderno:cuaderno@localhost:5432/cuaderno_test python -m pytest -q
# Sin Python 3.12 local: en un contenedor, contra la db de compose
docker run --rm --network cuaderno-app_default -v "$PWD":/repo -w /repo/backend \
  -e CUADERNO_DATABASE_URL=postgresql+psycopg://cuaderno:cuaderno@db:5432/cuaderno_test python:3.12-slim \
  sh -c "pip install -q -r requirements-dev.txt && python -m pytest -q"

cd app && flutter analyze && flutter test
cd app && dart run build_runner build           # tras cambiar las tablas de core/local/local_db.dart
cd app && flutter test --update-goldens         # tras cambiar a propósito el dibujo de una gráfica
cd app && CUADERNO_LIVE=http://localhost:8000 flutter test test/sync_live_test.dart   # crea cuentas prueba-sync-…: bórralas
cd app && flutter run -d macos
cd app && flutter run -d chrome --web-port 8080 # 8080: el puerto permitido en CORS
cd app && flutter run --dart-define=API_URL=http://<ip-tailscale-del-pc>:8000
```

`pytest` a secas no encuentra el paquete `app`: usa `python -m pytest`. En el Mac de Nico, Flutter está en `~/Downloads/fluter/flutter/bin` (puede no estar en el PATH del asistente).

## Vocabulario y reglas del dominio

- **Programa / plan** → días (`program_days`) → huecos (`program_slots`). Un plan tiene de 1 a 4 semanas que se repiten; cada día lleva su semana y su key es única por (plan, semana). La misma key en varias semanas es «el mismo día» (comparte historial y alternativa elegida). **Semana actual** = ((fecha − `program_started_on`) en días ÷ 7, entero) mód semanas + 1. Las plantillas (sin dueño) no se editan: se duplican. El plan activo no se borra.
- **Hueco**: el ejercicio original, series, rango (`rep_min`–`rep_max`) y descanso.
- **Alternativa**: ejercicio que puede sustituir al del hueco (`exercise_alternatives`). Cada serie guarda `slot_exercise_id` (el del hueco) y `exercise_id` (el que se hizo); el historial y las sugerencias van por `exercise_id`. En un día no se repite un ejercicio. Si la sesión anterior de ese día usó una alternativa, el plan propone la misma.
- **unit**: reps o seconds. Una alternativa hereda el rango del hueco, salvo que cambie de unidad y tenga rango propio (`default_rep_min/max`).
- **load_mode**: kg = peso de la carga; extra = lastre sobre el peso corporal (0 = sin lastre). Dominadas, fondos, crunch y plancha usan extra.
- **Doble progresión**: todas las series al máximo del rango con el mismo peso → sube (2,5 kg en básicos, 1–2 kg en aislamiento, +2,5 kg de lastre o +10 s); alguna serie por debajo del mínimo → repite el peso; si no → mismo peso, +1 rep. Sin historial → mensaje de primera vez.
- **Grasa estimada**: masa magra = peso inicial × (1 − grasa inicial). Peso objetivo para X % = masa magra ÷ (1 − X/100). Ritmo semanal sobre la media semanal: ≤ −1,1 % rápido, ≤ −0,4 % en ritmo, ≤ −0,15 % lento; si no, estancado.
- **Comidas**: valores por 100 g. El diario y los platos copian los valores al guardar (no cambian si luego se edita o borra el alimento). Si un día tiene diario, sus kcal y proteína mandan sobre las apuntadas a mano.
- **Peso de la báscula** (`weight_source = health`): rellena Peso solo si ese día no hay peso apuntado a mano; corregirlo a mano lo hace manual y la sincronización ya no lo toca.
- **Pulsera**: resumen por día (`daily_metrics`: pasos, kcal activas, sueño, pulso en reposo, VFC) y actividades. En el móvil, para no contar dos veces: pasos = total del día de Health Connect; kcal y sueño = la fuente que más marca; peso = el primero del día; pulso y VFC = media del día. El sueño cuenta para el día en que te despiertas.
- **Ejercicios propios**: id `u:…`, figura genérica, hasta 6 fotos/GIF/vídeos (fotos ≤ 10 MB, vídeos ≤ 50 MB; tipo por los bytes; HEIC no). Las URL de los archivos van firmadas y caducan; en local solo se guardan los id. No se borran (pueden estar en planes o historial).
- **Figuras**: JSON con poses a y b (hip, t en grados, hand, foot, opcionales hand2/foot2/toe), props, gear, y parámetros fs, ls, tl, ho, eb, kb, front. Lienzo 200 × 170, suelo en y = 160. Si tocas la matemática, `figure_test.dart` tiene que seguir pasando.

## Sincronización (la app sin conexión)

- La app **lee y escribe en la base local** (drift). Cada cambio va a la cola (`Outbox`) y el sincronizador la envía en orden (`POST /sync/push`) y descarga lo nuevo (`GET /sync/pull?since=cursor`). Sincroniza al abrir, un segundo después de cada cambio, al volver a la app, cada 30 s si hay pendientes y con el botón del icono de estado.
- Cada registro tiene `version`. Si al enviar no coincide con la del servidor, es un **conflicto** y el usuario elige en la pantalla de sincronización («lo mío» se reenvía con un `op_id` nuevo; «lo del servidor» descarta lo local). Reenviar el mismo `op_id` no aplica nada dos veces.
- Los id los crea la app: `u:` + 12 hex (alimentos, ejercicios y planes propios), UUID (platos, entradas del diario), `AAAA-MM-DD` (registros de Peso, días de la pulsera), `AAAA-MM-DD/day_key` (sesiones), `me` (perfil).
- **Backend**: `sync/tracking.py` anota en `sync_log` todo cambio en una tabla sincronizada, venga por `/sync/push`, por los endpoints de siempre o por `/health/sync`. Un `DELETE`/`UPDATE` masivo en esas tablas falla a propósito: borra o cambia registro a registro. La versión sube una vez por transacción.
- **Para sincronizar un tipo nuevo**: `version` + `updated_at` en el modelo (con migración), su entrada en `TRACKED` (y en `PARENTS` si sus hijos van dentro de su JSON), su `Entity` en `sync/entities.py`, tests; en la app, sube `SyncEngine.scope` (fuerza una descarga completa), añade sus etiquetas en `sync_widgets.dart` y, si el servidor calculaba algo, su versión en Dart.
- **Lógica duplicada en Dart, que tiene que coincidir con el backend** (los tests usan los mismos casos y el catálogo real): `planner.dart` ↔ `progression.py`, `schedule.py` y `routers/workouts.py`; `computeSummary` en `body/models.dart` ↔ `services/body.py`; `Dish.fromSync`/`DishDraft` ↔ `dish_out`; `searchFoods` ↔ `GET /foods`; `roundHalfEven` = `round()` de Python. Si cambias una, cambia la otra.
- Datos comunes (alimentos y ejercicios del catálogo, alternativas, plantillas) llegan por `GET /sync/reference` con hash y se guardan en `Meta`.
- Necesitan conexión: iniciar sesión, subir fotos y vídeos, leer la pulsera (envía a `/health/sync`) e importar el cuaderno web.

## Convenciones

- Todo texto visible en español, en frases cortas. Los errores dicen qué pasó y cómo arreglarlo, sin disculpas («Apunta al menos una serie antes de guardar.»).
- Backend: un router por área, validación con Pydantic `Field`, `HTTPException` con detail en español. Cualquier cambio en `models.py` lleva su migración Alembic revisada (`test_migrations` comprueba que coinciden). Ojo con la FK circular `programs.owner_id` ↔ `users.program_id`: mira cómo se resolvió en la 0001. Cada endpoint nuevo lleva su test.
- Flutter: un repositorio por feature; las pantallas leen de proveedores sobre la base local (`localRecordsProvider`) y se actualizan solas, sin invalidar a mano; las escrituras van por el repositorio (`SyncEngine.put/remove` + `syncController.changed()`). La lógica, en clases sin Flutter para poder probarla. Widgets sin lógica de red. Coma decimal aceptada en los números. Respeta el tema (nada de colores fijos salvo los de `theme.dart`) y «reducir movimiento».
- Dart: el pubspec permite Dart 3.6, así que nada de sintaxis de 3.8 (elementos `?x` en listas y mapas).
- Fechas: cuenta días por calendario (`daysBetween`, `daysBefore`), nunca con `Duration`: los cambios de hora desplazan un día.
- Gráficas: barras desde cero, líneas de 2 px, rejilla fina y continua, valor del día al tocar, y siempre una alternativa en texto (lista de días). Revisa las imágenes de `test/goldens/` tras cambiarlas.
- No cambies el formato de `catalog.json` ni el del importador sin avisar: el cuaderno web y los datos de Nico dependen de ellos.

## Estado

Hecho, backend y app, con tests: cuentas; entreno con alternativas, sugerencias y planes de 1–4 semanas con editor; ejercicios propios con fotos y vídeos; comidas (diario, alimentos propios, platos); peso (media 7 días, grasa estimada, ritmo semanal, gráfica); pulsera (Health Connect en Android); pestaña Salud; Guía; importador; modo sin conexión con sincronización y resolución de conflictos.

Pendiente:
- Probar en un móvil real: lectura de Health Connect con la pulsera, modo sin conexión y pantallas a mano.
- Para Google Play: borrar la cuenta desde la app (la base ya lo permite; falta endpoint, opción en la app y borrar sus fotos del disco), política de privacidad (el enlace de Health Connect hoy abre la app) y declaración de datos de salud, versión release (nombre, icono, firma, `applicationId`), https.
- Servidor: `CUADERNO_JWT_SECRET` propio, copias de seguridad de Postgres y del volumen `media`, limpieza periódica de `sync_ops`/`sync_log`.
- iPhone: activar HealthKit en Xcode y probar una compilación iOS.
- Mejoras: cola de fotos y vídeos sin conexión, editar entradas del diario y alimentos propios, más de 30 días de historial de la pulsera, miniaturas de vídeo, CI en GitHub.

## Siguiente tarea

Por decidir. Propuesta: probarlo en el móvil de Nico y, después, borrar la cuenta y la política de privacidad, que son requisito para publicar.
