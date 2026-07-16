"""
Latency Budget System
=====================
Manages end-to-end latency targets with graceful degradation.
If a stage exceeds its budget, we fall back to faster/smaller options.
"""

import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


class BudgetTier(Enum):
    FAST = "fast"        # < 1.5s total
    NORMAL = "normal"    # < 3s total
    QUALITY = "quality"  # < 6s total


@dataclass
class StageBudget:
    name: str
    budget_ms: float
    elapsed_ms: float = 0.0
    degraded: bool = False


@dataclass
class LatencyBudget:
    tier: BudgetTier = BudgetTier.NORMAL
    stages: list = field(default_factory=list)
    _start: float = 0.0
    _stage_start: float = 0.0

    def __post_init__(self):
        self._start = time.time()
        self._stage_start = self._start
        # Default budgets per tier (milliseconds)
        budgets = {
            BudgetTier.FAST: {
                "prebuffer": 50,
                "vad": 80,
                "asr": 600,
                "llm_clean": 200,
                "llm_transform": 200,
                "context_fetch": 100,
                "paste": 50,
            },
            BudgetTier.NORMAL: {
                "prebuffer": 100,
                "vad": 150,
                "asr": 1500,
                "llm_clean": 400,
                "llm_transform": 400,
                "context_fetch": 200,
                "paste": 50,
            },
            BudgetTier.QUALITY: {
                "prebuffer": 200,
                "vad": 300,
                "asr": 3500,
                "llm_clean": 800,
                "llm_transform": 800,
                "context_fetch": 300,
                "paste": 50,
            },
        }
        self._budgets = budgets[self.tier]
        for name, ms in self._budgets.items():
            self.stages.append(StageBudget(name=name, budget_ms=ms))

    def start_stage(self, name: str) -> "LatencyBudget":
        self._stage_start = time.time()
        stage = self._find_stage(name)
        if stage:
            stage.elapsed_ms = 0
            stage.degraded = False
        return self

    def end_stage(self, name: str) -> float:
        """End a stage, return elapsed ms. Marks degraded if over budget."""
        elapsed = (time.time() - self._stage_start) * 1000
        stage = self._find_stage(name)
        if stage:
            stage.elapsed_ms = elapsed
            if elapsed > stage.budget_ms:
                stage.degraded = True
        return elapsed

    def remaining_budget(self, name: str) -> float:
        """How many ms remain for this stage."""
        stage = self._find_stage(name)
        if stage:
            return max(0, stage.budget_ms - stage.elapsed_ms)
        return 0

    def total_elapsed(self) -> float:
        return (time.time() - self._start) * 1000

    def should_degrade(self, name: str) -> bool:
        """True if we should use a faster/smaller variant for this stage."""
        stage = self._find_stage(name)
        if stage and stage.degraded:
            return True
        # Also degrade if overall budget is tight
        total_budget = sum(s.budget_ms for s in self.stages)
        if self.total_elapsed() > total_budget * 0.7:
            return True
        return False

    def summary(self) -> str:
        lines = [f"Latency Budget ({self.tier.value}) — {self.total_elapsed():.0f}ms total"]
        for s in self.stages:
            flag = " ⚠️" if s.degraded else ""
            pct = (s.elapsed_ms / s.budget_ms * 100) if s.budget_ms > 0 else 0
            lines.append(f"  {s.name}: {s.elapsed_ms:.0f}/{s.budget_ms:.0f}ms ({pct:.0f}%){flag}")
        return "\n".join(lines)

    def _find_stage(self, name: str) -> Optional[StageBudget]:
        for s in self.stages:
            if s.name == name:
                return s
        return None
