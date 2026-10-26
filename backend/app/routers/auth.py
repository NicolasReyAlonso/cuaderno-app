import shutil
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Response, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import select

from ..models import User
from ..schemas import DeleteAccountIn, RegisterIn, TokenOut, UserOut, UserPatch
from ..security import DB, CurrentUser, create_access_token, hash_password, verify_password
from ..seed import DEFAULT_PROGRAM
from ..services import media

router = APIRouter(tags=["cuenta"])


@router.post("/auth/register", response_model=TokenOut, status_code=status.HTTP_201_CREATED)
def register(body: RegisterIn, db: DB):
    email = body.email.lower()
    if db.scalar(select(User).where(User.email == email)):
        raise HTTPException(status.HTTP_409_CONFLICT, "Ya existe una cuenta con ese correo.")
    user = User(email=email, password_hash=hash_password(body.password), name=body.name, program_id=DEFAULT_PROGRAM)
    db.add(user)
    db.commit()
    return TokenOut(access_token=create_access_token(str(user.id)))


@router.post("/auth/login", response_model=TokenOut)
def login(form: Annotated[OAuth2PasswordRequestForm, Depends()], db: DB):
    user = db.scalar(select(User).where(User.email == form.username.lower()))
    if user is None or not verify_password(form.password, user.password_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Correo o contraseña incorrectos.")
    return TokenOut(access_token=create_access_token(str(user.id)))


@router.get("/me", response_model=UserOut)
def me(user: CurrentUser):
    return user


@router.patch("/me", response_model=UserOut)
def update_me(body: UserPatch, user: CurrentUser, db: DB):
    for k, v in body.model_dump(exclude_unset=True).items():
        setattr(user, k, v)
    db.commit()
    return user


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
def delete_me(body: DeleteAccountIn, user: CurrentUser, db: DB):
    """Borra la cuenta con todos sus datos y sus fotos y vídeos del disco. No se puede deshacer."""
    if not verify_password(body.password, user.password_hash):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "La contraseña no es correcta. Escríbela de nuevo para borrar la cuenta.")
    folder = media.media_root() / str(user.id)
    db.delete(user)  # el resto (planes, series, comidas, peso, pulsera, fotos…) se va con ON DELETE CASCADE
    db.commit()
    shutil.rmtree(folder, ignore_errors=True)  # después de confirmar: si falla la base, no se pierden los archivos
    return Response(status_code=status.HTTP_204_NO_CONTENT)
