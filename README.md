# Cuaderno de definición

App de entreno, comidas y peso para Android, iPhone y web.

- `backend/`: API en **FastAPI + SQLAlchemy 2 + PostgreSQL**, con migraciones Alembic.
- `app/`: app **Flutter** (un solo código para Android, iOS y web).
- `datos/cuaderno_export.json`: tus datos del cuaderno web (sesiones, comidas, peso, alimentos) listos para importar.

## 1. Arrancar el backend

Con Docker (lo más rápido):

```bash
docker compose up --build
# API en http://localhost:8000 · documentación interactiva en http://localhost:8000/docs
```

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
createdb cuaderno_test
CUADERNO_DATABASE_URL=postgresql+psycopg://USUARIO@localhost:5432/cuaderno_test pytest
```

## 2. Importar tus datos del cuaderno web

1. Crea tu cuenta desde la app o en `/docs` → `POST /auth/register`.
2. Pulsa *Authorize* en `/docs` con tu correo y contraseña.
3. `POST /import/cuaderno` con el contenido de `datos/cuaderno_export.json`, añadiendo tu punto de partida:

```json
"inicio": {"fecha": "2026-10-19", "peso": 99, "grasa": 30.7}
```

Se puede repetir sin duplicar nada: reemplaza las fechas que ya existan.

## 3. Arrancar la app Flutter

Las carpetas de plataforma (`android/`, `ios/`, `web/`) se generan una vez con Flutter:

```bash
cd app
flutter create . --platforms=android,ios,web --project-name cuaderno --org es.nico
flutter pub get
flutter test

# Web (el puerto 8080 ya está permitido en CORS)
flutter run -d chrome --web-port 8080

# Emulador Android: el ordenador es 10.0.2.2
flutter run --dart-define=API_URL=http://10.0.2.2:8000

# Móvil real en la misma wifi: usa la IP del ordenador
flutter run --dart-define=API_URL=http://192.168.1.X:8000
```

Para iPhone necesitas un Mac con Xcode; en un iPhone real, firma con tu Apple ID desde Xcode.

## Estado

| Parte | Backend | App |
|---|---|---|
| Cuenta (registro, login, sesión) | ✅ | ✅ |
| Entreno: plan del día, alternativas, historial, sugerencias, guardar | ✅ | ✅ |
| Muñecos animados de los 61 ejercicios | ✅ (catálogo) | ✅ |
| Comidas: alimentos, mis alimentos, platos, diario | ✅ | Fase 2 |
| Peso: media 7 días, grasa estimada, ritmo semanal | ✅ | Fase 2 |
| Importar el cuaderno web | ✅ | — |

Más detalle en el documento de arquitectura.
=======
# cuaderno-app
App to track nutrition, gym excercises etc
