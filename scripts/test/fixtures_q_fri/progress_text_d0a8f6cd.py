import math
from typing import Optional


def format_position(seconds: float | None) -> str:
    """Format a position in seconds as m:ss or h:mm:ss.

    Handles None, negative, NaN, and inf values by returning '0:00'.
    Floors the seconds value before formatting.
    """
    if seconds is None or not math.isfinite(seconds) or seconds < 0:
        return "0:00"

    total_seconds = int(math.floor(seconds))
    hours, remainder = divmod(total_seconds, 3600)
    minutes, secs = divmod(remainder, 60)

    if hours > 0:
        return f"{hours}:{minutes:02d}:{secs:02d}"
    return f"{minutes}:{secs:02d}"


def remaining_text(position_seconds: Optional[float], duration_seconds: Optional[float]) -> str:
    """Return a human-readable remaining time phrase.

    Returns '' if duration is missing or zero.
    Returns 'Finished' if position >= 90% of duration.
    Otherwise returns '<n> min left' where n is ceil(remaining/60), minimum 1.
    """
    if duration_seconds is None or duration_seconds <= 0:
        return ""

    pos = position_seconds if (position_seconds is not None and math.isfinite(position_seconds) and position_seconds >= 0) else 0

    if pos >= 0.9 * duration_seconds:
        return "Finished"

    remaining = duration_seconds - pos
    minutes = max(1, math.ceil(remaining / 60))
    return f"{minutes} min left"
def remaining_text(position_seconds: float | None, duration_seconds: float | None) -> str:
    """Return a human-readable remaining time phrase.

    Returns '' if duration is missing or zero.
    Returns 'Finished' if position >= 90% of duration.
    Otherwise returns '<n> min left' where n is ceil(remaining/60), minimum 1.
    """
    if duration_seconds is None or duration_seconds <= 0:
        return ""

    pos = position_seconds if (position_seconds is not None and math.isfinite(position_seconds) and position_seconds >= 0) else 0

    if pos >= 0.9 * duration_seconds:
        return "Finished"

    remaining = duration_seconds - pos
    minutes = max(1, math.ceil(remaining / 60))
    return f"{minutes} min left"
