"""
Description: pytest configuration for the function tests.
Description: Adds function/ to sys.path so `import src.X` resolves when tests run from function/.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

FIXTURE_DIR = Path(__file__).parent / "fixtures"


def load_fixture(name: str) -> dict:
    with (FIXTURE_DIR / name).open("r", encoding="utf-8") as f:
        return json.load(f)
