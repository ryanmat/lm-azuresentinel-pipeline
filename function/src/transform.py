"""
Description: Convert raw LM webhook JSON into a NormalizedAlert for the LogicMonitorAlerts_CL table.
Description: Handles the three LM datetime quirks: integer epoch, formatted string, or placeholder text.
"""
from __future__ import annotations

from datetime import UTC, datetime

from .models import LMAlertRaw, NormalizedAlert

# LM emits these literal strings for unset datetime fields on test alerts and active-only alerts.
_DATETIME_SENTINELS = frozenset({
    "",
    "Alert Clear Value",
    "##CLEARVALUE##",
    "##START##",
})


def parse_lm_datetime(value: str | None) -> datetime | None:
    """Parse LM's datetime formats.

    LM's webhook uses whichever format the alert emitter chose:
      - Integer epoch seconds (e.g. '1776708894') for some alert sources
      - Formatted string 'YYYY-MM-DD HH:MM:SS GMT' (confirmed for test alerts 2026-04-20)
      - Literal placeholder text ('Alert Clear Value') when the field is unset
    """
    if value is None or value.strip() in _DATETIME_SENTINELS:
        return None

    value = value.strip()

    try:
        return datetime.fromtimestamp(int(value), tz=UTC)
    except (ValueError, TypeError):
        pass

    for suffix in (" GMT", " UTC", " Z"):
        if value.endswith(suffix):
            value_naive = value[: -len(suffix)].strip()
            try:
                return datetime.strptime(value_naive, "%Y-%m-%d %H:%M:%S").replace(tzinfo=UTC)
            except ValueError:
                break

    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def transform(raw_payload: dict) -> NormalizedAlert:
    """Map a parsed LM webhook payload dict to a NormalizedAlert.
    Uses the raw payload's startEpoch for TimeGenerated; falls back to ingestion time if absent."""
    lm = LMAlertRaw.model_validate(raw_payload)

    started = parse_lm_datetime(lm.startEpoch)
    if started is None:
        started = datetime.now(tz=UTC)

    cleared = parse_lm_datetime(lm.clearEpoch)
    ack_user = lm.ackUser if lm.ackUser else None

    return NormalizedAlert(
        TimeGenerated=started,
        LmAlertId=lm.alertId or "unknown",
        AlertType=lm.alertType or "",
        Severity=lm.severity or "",
        Status=lm.status or "",
        DeviceName=lm.deviceName or "",
        DeviceDisplayName=lm.deviceDisplayName or "",
        DeviceGroups=lm.deviceGroups or "",
        DataSourceOrGroup=lm.dataSourceOrGroup or "",
        InstanceName=lm.instanceName or "",
        DataPointName=lm.dataPointName or "",
        DataPointValue=lm.dataPointValue or "",
        ThresholdValue=lm.thresholdValue or "",
        AlertMessage=lm.alertMessage or "",
        StartedTime=started,
        ClearedTime=cleared,
        AckUser=ack_user,
        PortalUrl=lm.portalUrl or "",
        RawAlert=raw_payload,
    )
