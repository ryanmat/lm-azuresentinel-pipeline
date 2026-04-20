"""
Description: Unit tests for src.transform covering LM datetime parsing and payload normalization.
Description: Fixtures in tests/fixtures/ represent captured-live and synthesized LM alert payloads.
"""
from __future__ import annotations

from datetime import UTC, datetime

import pytest

from src.transform import parse_lm_datetime, transform
from tests.conftest import load_fixture


class TestParseLMDatetime:
    def test_integer_epoch_parses_to_utc(self) -> None:
        result = parse_lm_datetime("1776709200")
        assert result == datetime(2026, 4, 20, 18, 20, 0, tzinfo=UTC)

    def test_formatted_string_with_gmt_suffix(self) -> None:
        result = parse_lm_datetime("2026-04-20 18:54:36 GMT")
        assert result == datetime(2026, 4, 20, 18, 54, 36, tzinfo=UTC)

    def test_formatted_string_with_utc_suffix(self) -> None:
        result = parse_lm_datetime("2026-04-20 18:54:36 UTC")
        assert result == datetime(2026, 4, 20, 18, 54, 36, tzinfo=UTC)

    def test_empty_string_returns_none(self) -> None:
        assert parse_lm_datetime("") is None

    def test_whitespace_only_returns_none(self) -> None:
        assert parse_lm_datetime("   ") is None

    def test_alert_clear_value_sentinel_returns_none(self) -> None:
        assert parse_lm_datetime("Alert Clear Value") is None

    def test_unsubstituted_token_returns_none(self) -> None:
        assert parse_lm_datetime("##CLEARVALUE##") is None
        assert parse_lm_datetime("##START##") is None

    def test_none_input_returns_none(self) -> None:
        assert parse_lm_datetime(None) is None

    def test_garbage_returns_none(self) -> None:
        assert parse_lm_datetime("not a date") is None

    def test_iso8601_with_z_suffix(self) -> None:
        result = parse_lm_datetime("2026-04-20T18:54:36Z")
        assert result == datetime(2026, 4, 20, 18, 54, 36, tzinfo=UTC)


class TestTransformTestAlert:
    def test_maps_test_alert_with_formatted_startepoch(self) -> None:
        payload = load_fixture("lm_test_alert.json")
        result = transform(payload)

        assert result.LmAlertId == "LMD0"
        assert result.AlertType == "alert"
        assert result.Severity == "ok"
        assert result.Status == "test"
        assert result.DeviceName == "Host"
        assert result.StartedTime == datetime(2026, 4, 20, 18, 54, 36, tzinfo=UTC)
        assert result.TimeGenerated == datetime(2026, 4, 20, 18, 54, 36, tzinfo=UTC)
        assert result.ClearedTime is None
        assert result.AckUser is None
        assert result.PortalUrl.startswith("https://")

    def test_raw_alert_preserved(self) -> None:
        payload = load_fixture("lm_test_alert.json")
        result = transform(payload)
        assert result.RawAlert == payload
        assert result.RawAlert["eventSource"] == ""


class TestTransformDatapointAlert:
    def test_maps_datapoint_alert_with_integer_startepoch(self) -> None:
        payload = load_fixture("lm_datapoint_alert.json")
        result = transform(payload)

        assert result.LmAlertId == "LMD362853019"
        assert result.Severity == "critical"
        assert result.Status == "active"
        assert result.DeviceName == "openclaw-vm"
        assert result.DataSourceOrGroup == "Precursor Predictive"
        assert result.DataPointName == "PredictedLatencyP95"
        assert result.DataPointValue == "4200.0"
        assert result.ThresholdValue == "> 3000"
        assert result.StartedTime == datetime(2026, 4, 20, 18, 20, 0, tzinfo=UTC)
        assert result.ClearedTime is None

    def test_device_groups_preserved_as_string(self) -> None:
        payload = load_fixture("lm_datapoint_alert.json")
        result = transform(payload)
        assert result.DeviceGroups == "/Servers/Linux,/Ryan Lab"


class TestTransformLogAlert:
    def test_maps_logalert_with_empty_datapoint_fields(self) -> None:
        payload = load_fixture("lm_logalert.json")
        result = transform(payload)

        assert result.DataSourceOrGroup == "openclaw-auth-failures"
        assert result.InstanceName == ""
        assert result.DataPointName == ""
        assert result.AlertMessage.startswith("Failed password for root")


class TestTransformEdgeCases:
    def test_missing_alert_id_fallback(self) -> None:
        result = transform({"severity": "warning"})
        assert result.LmAlertId == "unknown"

    def test_empty_ack_user_becomes_none(self) -> None:
        result = transform({"alertId": "x", "ackUser": ""})
        assert result.AckUser is None

    def test_populated_ack_user_preserved(self) -> None:
        result = transform({"alertId": "x", "ackUser": "rmatuszewski"})
        assert result.AckUser == "rmatuszewski"

    def test_startepoch_unset_falls_back_to_now(self) -> None:
        result = transform({"alertId": "x"})
        delta = (datetime.now(tz=UTC) - result.StartedTime).total_seconds()
        assert delta < 5

    @pytest.mark.parametrize("extra_key", ["unknownField", "newLmFeature", "customCol"])
    def test_unknown_fields_kept_in_raw(self, extra_key: str) -> None:
        payload = {"alertId": "x", extra_key: "value"}
        result = transform(payload)
        assert result.RawAlert[extra_key] == "value"


class TestToDCRRow:
    def test_dropped_none_fields_not_in_output(self) -> None:
        payload = load_fixture("lm_test_alert.json")
        row = transform(payload).to_dcr_row()
        assert "ClearedTime" not in row
        assert "AckUser" not in row

    def test_iso_datetimes_with_z_suffix(self) -> None:
        payload = load_fixture("lm_datapoint_alert.json")
        row = transform(payload).to_dcr_row()
        assert row["TimeGenerated"].endswith("Z")
        assert row["StartedTime"].endswith("Z")

    def test_raw_alert_stays_dict(self) -> None:
        payload = load_fixture("lm_test_alert.json")
        row = transform(payload).to_dcr_row()
        assert isinstance(row["RawAlert"], dict)
        assert row["RawAlert"]["alertId"] == "LMD0"

    def test_all_required_columns_present(self) -> None:
        payload = load_fixture("lm_datapoint_alert.json")
        row = transform(payload).to_dcr_row()
        expected = {
            "TimeGenerated", "LmAlertId", "AlertType", "Severity", "Status",
            "DeviceName", "DeviceDisplayName", "DeviceGroups", "DataSourceOrGroup",
            "InstanceName", "DataPointName", "DataPointValue", "ThresholdValue",
            "AlertMessage", "StartedTime", "PortalUrl", "RawAlert",
        }
        assert expected.issubset(row.keys())
