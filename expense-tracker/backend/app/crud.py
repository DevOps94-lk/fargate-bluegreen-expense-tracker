from __future__ import annotations

import datetime
from sqlalchemy import extract, func
from sqlalchemy.orm import Session, joinedload

from app.models import Category, Expense
from app.schemas import CategoryCreate, ExpenseCreate, ExpenseUpdate


# ── Category ──────────────────────────────────────────────────────────────────

def get_categories(db: Session) -> list[Category]:
    return db.query(Category).order_by(Category.name).all()


def get_category(db: Session, category_id: int) -> Category | None:
    return db.query(Category).filter(Category.id == category_id).first()


def create_category(db: Session, data: CategoryCreate) -> Category:
    category = Category(**data.model_dump())
    db.add(category)
    db.commit()
    db.refresh(category)
    return category


def seed_default_categories(db: Session) -> None:
    defaults = [
        {"name": "Food",          "color": "#f97316"},
        {"name": "Transport",     "color": "#3b82f6"},
        {"name": "Housing",       "color": "#8b5cf6"},
        {"name": "Entertainment", "color": "#ec4899"},
        {"name": "Health",        "color": "#10b981"},
        {"name": "Shopping",      "color": "#f59e0b"},
        {"name": "Education",     "color": "#06b6d4"},
        {"name": "Other",         "color": "#6b7280"},
    ]
    for item in defaults:
        if not db.query(Category).filter(Category.name == item["name"]).first():
            db.add(Category(**item))
    db.commit()


# ── Expense ───────────────────────────────────────────────────────────────────

def get_expenses(
    db: Session,
    skip: int = 0,
    limit: int = 100,
    category_id: int | None = None,
    start_date: datetime.date | None = None,
    end_date: datetime.date | None = None,
) -> list[Expense]:
    query = db.query(Expense).options(joinedload(Expense.category))
    if category_id:
        query = query.filter(Expense.category_id == category_id)
    if start_date:
        query = query.filter(Expense.date >= start_date)
    if end_date:
        query = query.filter(Expense.date <= end_date)
    return query.order_by(Expense.date.desc()).offset(skip).limit(limit).all()


def get_expense(db: Session, expense_id: int) -> Expense | None:
    return (
        db.query(Expense)
        .options(joinedload(Expense.category))
        .filter(Expense.id == expense_id)
        .first()
    )


def create_expense(db: Session, data: ExpenseCreate) -> Expense:
    expense = Expense(**data.model_dump())
    db.add(expense)
    db.commit()
    db.refresh(expense)
    return get_expense(db, expense.id)


def update_expense(db: Session, expense_id: int, data: ExpenseUpdate) -> Expense | None:
    expense = db.query(Expense).filter(Expense.id == expense_id).first()
    if not expense:
        return None
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(expense, field, value)
    db.commit()
    db.refresh(expense)
    return get_expense(db, expense_id)


def delete_expense(db: Session, expense_id: int) -> bool:
    expense = db.query(Expense).filter(Expense.id == expense_id).first()
    if not expense:
        return False
    db.delete(expense)
    db.commit()
    return True


def get_summary(
    db: Session,
    start_date: datetime.date | None = None,
    end_date: datetime.date | None = None,
) -> dict:
    query = db.query(Expense)
    if start_date:
        query = query.filter(Expense.date >= start_date)
    if end_date:
        query = query.filter(Expense.date <= end_date)

    total = query.with_entities(func.sum(Expense.amount)).scalar() or 0.0
    count = query.count()

    cat_query = (
        db.query(
            Category.name,
            Category.color,
            func.sum(Expense.amount).label("total"),
            func.count(Expense.id).label("count"),
        )
        .join(Expense, Expense.category_id == Category.id)
    )
    if start_date:
        cat_query = cat_query.filter(Expense.date >= start_date)
    if end_date:
        cat_query = cat_query.filter(Expense.date <= end_date)
    by_category = (
        cat_query
        .group_by(Category.id, Category.name, Category.color)
        .order_by(func.sum(Expense.amount).desc())
        .all()
    )

    monthly = (
        db.query(
            extract("year", Expense.date).label("year"),
            extract("month", Expense.date).label("month"),
            func.sum(Expense.amount).label("total"),
        )
        .group_by("year", "month")
        .order_by("year", "month")
        .all()
    )

    return {
        "total": float(total),
        "count": count,
        "by_category": [
            {"name": r.name, "color": r.color, "total": float(r.total), "count": r.count}
            for r in by_category
        ],
        "monthly_totals": [
            {"year": int(r.year), "month": int(r.month), "total": float(r.total)}
            for r in monthly
        ],
    }
