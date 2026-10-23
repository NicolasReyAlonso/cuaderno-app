from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="CUADERNO_", extra="ignore")

    database_url: str = "postgresql+psycopg://cuaderno:cuaderno@localhost:5432/cuaderno"
    jwt_secret: str = "cambia-esto-en-produccion"
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 60 * 24 * 30
    cors_origins: list[str] = ["http://localhost:8080", "http://localhost:5000", "http://127.0.0.1:8080"]
    seed_on_startup: bool = True


@lru_cache
def get_settings() -> Settings:
    return Settings()
