# Cuaderno de definición

App de gimnasio para una fase de definición: entrenos con sugerencias de progresión, planes por semanas, comidas, peso, datos de la pulsera y una guía. Funciona en Android, iPhone, macOS y web, también sin conexión: guarda todo en el dispositivo y lo sincroniza con el servidor cuando está disponible.

- `backend/`: API en **FastAPI + SQLAlchemy 2 + PostgreSQL**, con migraciones Alembic.
- `app/`: app **Flutter** (un solo código para Android, iOS, macOS y web) con base local **drift** (SQLite).
- `datos/cuaderno_export.json`: los datos del cuaderno web (sesiones, comidas, peso, alimentos) listos para importar.

El contexto completo (arquitectura, reglas del dominio, sincronización y convenciones) está en [CLAUDE.md](CLAUDE.md).

## 1. Arrancar el backend

Con Docker (lo más rápido):

```bash
docker compose up --build
# API en http://localhost:8000 · documentación interactiva en http://localhost:8000/docs
```

Aplica las migraciones y carga el catálogo al arrancar. Las fotos y vídeos de los ejercicios se guardan en el volumen `media`.

Sin Docker:

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env          # ajusta CUADERNO_DATABASE_URL y CUADERNO_JWT_SECRET
alembic upgrade head          # crea las tablas
uvicorn app.main:app --reload # carga el catálogo al arrancar
```

Tests (necesitan una base de datos PostgreSQL vacía para pruebas):

```bash
createdb cuaderno_test        # con Docker: docker compose exec db createdb -U cuaderno cuaderno_test
cd backend
CUADERNO_DATABASE_URL=postgresql+psycopg://USUARIO@localhost:5432/cuaderno_test python -m pytest -q
```

Usa `python -m pytest`: con `pytest` a secas no encuentra el paquete `app`.

## 2. Arrancar la app

Las carpetas de cada plataforma ya están en el repositorio.

```bash
cd app
flutter pub get
flutter analyze && flutter test

flutter run -d macos                                              # Mac
flutter run -d chrome --web-port 8080                             # web (el puerto 8080 está permitido en CORS)
flutter run --dart-define=API_URL=http://10.0.2.2:8000            # emulador Android (el ordenador es 10.0.2.2)
flutter run --dart-define=API_URL=http://<ip-tailscale-del-pc>:8000  # móvil real por Tailscale
```

Si cambias las tablas de la base local (`lib/core/local/local_db.dart`), regenera su código con `dart run build_runner build`.

Para iPhone necesitas un Mac con Xcode y firmar con tu Apple ID; para leer la app Salud, activa además HealthKit en Xcode (Runner → Signing & Capabilities).

## 3. Importar los datos del cuaderno web

1. Crea tu cuenta desde la app o en `/docs` → `POST /auth/register`.
2. Pulsa *Authorize* en `/docs` con tu correo y contraseña.
3. `POST /import/cuaderno` con el contenido de `datos/cuaderno_export.json`, añadiendo tu punto de partida:

```json
"inicio": {"fecha": "2026-10-19", "peso": 99, "grasa": 30.7}
```

Se puede repetir sin duplicar nada: reemplaza las fechas que ya existan. La app recibe lo importado en la siguiente sincronización.

## Estado

| Parte | Backend | App | Sin conexión |
|---|---|---|---|
| Cuenta (registro, login, sesión) | ✅ | ✅ | — (iniciar sesión necesita el servidor) |
| Entreno: plan del día, alternativas, historial, sugerencias, guardar | ✅ | ✅ | ✅ |
| Planes de 1 a 4 semanas: crear, editar, duplicar, activar | ✅ | ✅ | ✅ |
| Ejercicios propios con fotos, GIF y vídeos | ✅ | ✅ | ✅ (subir archivos necesita conexión) |
| Muñecos animados de los 61 ejercicios | ✅ (catálogo) | ✅ | ✅ |
| Comidas: alimentos, mis alimentos, platos, diario | ✅ | ✅ | ✅ |
| Peso: media 7 días, grasa estimada, ritmo semanal, gráfica | ✅ | ✅ | ✅ |
| Pulsera y báscula (Health Connect; Salud en iPhone pendiente) | ✅ | ✅ | Se lee al volver la conexión |
| Pestaña Salud y Guía | — | ✅ | ✅ |
| Importar el cuaderno web | ✅ | — | — |

Pendiente: probar en un móvil real, los requisitos para publicar en Google Play (borrar la cuenta desde la app, política de privacidad, versión firmada, https) y el despliegue del servidor. La lista completa está en [CLAUDE.md](CLAUDE.md#estado).
