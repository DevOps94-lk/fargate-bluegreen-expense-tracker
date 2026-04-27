from __future__ import annotations

import datetime
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app import crud, schemas
from app.database import get_db

router = APIRouter(prefix="/api/expenses", tags=["expenses"])


@router.get("/", response_model=list[schemas.ExpenseResponse])
def list_expenses(
    skip: int = Query(default=0, ge=0),
    limit: int = Query(default=100, ge=1, le=500),
    category_id: int | None = None,
    start_date: datetime.date | None = None,
    end_date: datetime.date | None = None,
    db: Session = Depends(get_db),
):
    return crud.get_expenses(db, skip, limit, category_id, start_date, end_date)


@router.post("/", response_model=schemas.ExpenseResponse, status_code=status.HTTP_201_CREATED)
def create_expense(data: schemas.ExpenseCreate, db: Session = Depends(get_db)):
    if not crud.get_category(db, data.category_id):
        raise HTTPException(status_code=404, detail="Category not found")
    return crud.create_expense(db, data)


@router.get("/summary", response_model=schemas.SummaryResponse)
def get_summary(
    start_date: datetime.date | None = None,
    end_date: datetime.date | None = None,
    db: Session = Depends(get_db),
):
    return crud.get_summary(db, start_date, end_date)


@router.get("/{expense_id}", response_model=schemas.ExpenseResponse)
def get_expense(expense_id: int, db: Session = Depends(get_db)):
    expense = crud.get_expense(db, expense_id)
    if not expense:
        raise HTTPException(status_code=404, detail="Expense not found")
    return expense


@router.put("/{expense_id}", response_model=schemas.ExpenseResponse)
def update_expense(
    expense_id: int,
    data: schemas.ExpenseUpdate,
    db: Session = Depends(get_db),
):
    if data.category_id and not crud.get_category(db, data.category_id):
        raise HTTPException(status_code=404, detail="Category not found")
    expense = crud.update_expense(db, expense_id, data)
    if not expense:
        raise HTTPException(status_code=404, detail="Expense not found")
    return expense


@router.delete("/{expense_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_expense(expense_id: int, db: Session = Depends(get_db)):
    if not crud.delete_expense(db, expense_id):
        raise HTTPException(status_code=404, detail="Expense not found")
