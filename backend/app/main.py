from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import get_settings
from .routers import auth, body, catalog, health, importer, media, nutrition, programs, workouts


@asynccontextmanager
async def lifespan(app: FastAPI):
    if get_settings().seed_on_startup:
        from .db import SessionLocal
        from .seed import seed

        with SessionLocal() as db:
            seed(db)
    yield


app = FastAPI(title="Cuaderno de definición", version="0.1.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=get_settings().cors_origins, allow_credentials=True,
                   allow_methods=["*"], allow_headers=["*"])

for r in (auth.router, catalog.router, media.router, programs.router, workouts.router, body.router, health.router, nutrition.router, importer.router):
    app.include_router(r)


@app.get("/health", tags=["sistema"])
def health():
    return {"ok": True}
