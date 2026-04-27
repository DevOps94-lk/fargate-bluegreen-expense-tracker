from __future__ import annotations

import datetime
from pydantic import BaseModel, Field, ConfigDict


class CategoryBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=50)
    color: str = Field(default="#6366f1", pattern=r"^#[0-9a-fA-F]{6}$")


class CategoryCreate(CategoryBase):
    pass


class CategoryResponse(CategoryBase):
    model_config = ConfigDict(from_attributes=True)
    id: int


class ExpenseBase(BaseModel):
    title: str = Field(..., min_length=1, max_length=100)
    amount: float = Field(..., gt=0, description="Amount must be positive")
    date: datetime.date
    description: str | None = Field(default=None, max_length=500)
    category_id: int


class ExpenseCreate(ExpenseBase):
    pass


class ExpenseUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=100)
    amount: float | None = Field(default=None, gt=0)
    date: datetime.date | None = None
    description: str | None = Field(default=None, max_length=500)
    category_id: int | None = None


class ExpenseResponse(ExpenseBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
    category: CategoryResponse


class SummaryResponse(BaseModel):
    total: float
    count: int
    by_category: list[dict]
    monthly_totals: list[dict]
