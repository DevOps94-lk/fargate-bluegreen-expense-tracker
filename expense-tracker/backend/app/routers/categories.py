from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app import crud, schemas
from app.database import get_db

router = APIRouter(prefix="/api/categories", tags=["categories"])


@router.get("/", response_model=list[schemas.CategoryResponse])
def list_categories(db: Session = Depends(get_db)):
    return crud.get_categories(db)


@router.post("/", response_model=schemas.CategoryResponse, status_code=status.HTTP_201_CREATED)
def create_category(data: schemas.CategoryCreate, db: Session = Depends(get_db)):
    return crud.create_category(db, data)
