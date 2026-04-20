"""
Description: Pydantic models for raw LM webhook payloads and normalized DCR rows.
Description: The raw model is permissive (LM sends empty strings, placeholder text, variable types).
"""
from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class LMAlertRaw(BaseModel):
    """Raw LM webhook payload. All fields are optional strings because LM may emit empty
    strings or placeholder text for unset fields (e.g. clearEpoch = 'Alert Clear Value')."""

    model_config = ConfigDict(extra="allow")

    alertId: str | None = None
    alertType: str | None = None
    severity: str | None = None
    status: str | None = None
    deviceName: str | None = None
    deviceDisplayName: str | None = None
    deviceGroups: str | None = None
    dataSourceOrGroup: str | None = None
    instanceName: str | None = None
    dataPointName: str | None = None
    dataPointValue: str | None = None
    thresholdValue: str | None = None
    alertMessage: str | None = None
    startEpoch: str | None = None
    clearEpoch: str | None = None
    ackUser: str | None = None
    portalUrl: str | None = None
    eventSource: str | None = None


class NormalizedAlert(BaseModel):
    """Row written to LogicMonitorAlerts_CL. Column names MUST match the DCR stream schema."""

    TimeGenerated: datetime
    LmAlertId: str
    AlertType: str = ""
    Severity: str = ""
    Status: str = ""
    DeviceName: str = ""
    DeviceDisplayName: str = ""
    DeviceGroups: str = ""
    DataSourceOrGroup: str = ""
    InstanceName: str = ""
    DataPointName: str = ""
    DataPointValue: str = ""
    ThresholdValue: str = ""
    AlertMessage: str = ""
    StartedTime: datetime
    ClearedTime: datetime | None = None
    AckUser: str | None = None
    PortalUrl: str = ""
    RawAlert: dict = Field(default_factory=dict)

    def to_dcr_row(self) -> dict:
        """Serialize to the exact shape expected by the Logs Ingestion API.
        Datetimes must be ISO 8601 with Z suffix; None fields are dropped."""
        out: dict = {
            "TimeGenerated": self.TimeGenerated.isoformat().replace("+00:00", "Z"),
            "LmAlertId": self.LmAlertId,
            "AlertType": self.AlertType,
            "Severity": self.Severity,
            "Status": self.Status,
            "DeviceName": self.DeviceName,
            "DeviceDisplayName": self.DeviceDisplayName,
            "DeviceGroups": self.DeviceGroups,
            "DataSourceOrGroup": self.DataSourceOrGroup,
            "InstanceName": self.InstanceName,
            "DataPointName": self.DataPointName,
            "DataPointValue": self.DataPointValue,
            "ThresholdValue": self.ThresholdValue,
            "AlertMessage": self.AlertMessage,
            "StartedTime": self.StartedTime.isoformat().replace("+00:00", "Z"),
            "PortalUrl": self.PortalUrl,
            "RawAlert": self.RawAlert,
        }
        if self.ClearedTime is not None:
            out["ClearedTime"] = self.ClearedTime.isoformat().replace("+00:00", "Z")
        if self.AckUser:
            out["AckUser"] = self.AckUser
        return out
