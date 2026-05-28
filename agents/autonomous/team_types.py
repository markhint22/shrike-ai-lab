"""Shared output types for autonomous team workflows."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any


@dataclass
class TeamOutput:
    """Normalized response contract for all autonomous teams."""

    team: str
    mode: str
    summary: str
    actions: list[str] = field(default_factory=list)
    artifacts: list[str] = field(default_factory=list)
    metrics: dict[str, Any] = field(default_factory=dict)
    notes: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)
