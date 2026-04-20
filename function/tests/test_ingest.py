"""
Description: Unit tests for src.ingest LogsIngestionSink.
Description: Mocks the Azure LogsIngestionClient so tests run without real credentials or network.
"""
from __future__ import annotations

from unittest.mock import MagicMock, patch

from src.ingest import LogsIngestionSink


class TestLogsIngestionSink:
    def test_send_noop_on_empty_rows(self) -> None:
        sink = LogsIngestionSink(
            endpoint="https://dce.ingest.monitor.azure.com",
            dcr_immutable_id="dcr-abc123",
            stream_name="Custom-LogicMonitorAlerts_CL",
        )
        with patch("src.ingest.LogsIngestionClient") as mock_client_cls:
            sink.send([])
            mock_client_cls.assert_not_called()

    def test_send_uploads_with_correct_params(self) -> None:
        sink = LogsIngestionSink(
            endpoint="https://dce.ingest.monitor.azure.com",
            dcr_immutable_id="dcr-abc123",
            stream_name="Custom-LogicMonitorAlerts_CL",
        )
        with patch("src.ingest.LogsIngestionClient") as mock_client_cls, \
             patch("src.ingest.ManagedIdentityCredential"):
            mock_client = MagicMock()
            mock_client_cls.return_value = mock_client
            rows = [{"LmAlertId": "LMD1", "Severity": "critical"}]

            sink.send(rows)

            mock_client.upload.assert_called_once_with(
                rule_id="dcr-abc123",
                stream_name="Custom-LogicMonitorAlerts_CL",
                logs=rows,
            )

    def test_client_reused_across_calls(self) -> None:
        sink = LogsIngestionSink(
            endpoint="https://dce.ingest.monitor.azure.com",
            dcr_immutable_id="dcr-abc123",
            stream_name="Custom-LogicMonitorAlerts_CL",
        )
        with patch("src.ingest.LogsIngestionClient") as mock_client_cls, \
             patch("src.ingest.ManagedIdentityCredential"):
            mock_client_cls.return_value = MagicMock()

            sink.send([{"a": 1}])
            sink.send([{"b": 2}])

            assert mock_client_cls.call_count == 1

    def test_reads_config_from_env(self, monkeypatch) -> None:
        monkeypatch.setenv("DCE_ENDPOINT", "https://env-dce.ingest.monitor.azure.com")
        monkeypatch.setenv("DCR_IMMUTABLE_ID", "dcr-from-env")
        monkeypatch.setenv("DCR_STREAM_NAME", "Custom-FromEnv_CL")

        sink = LogsIngestionSink()
        assert sink.endpoint == "https://env-dce.ingest.monitor.azure.com"
        assert sink.dcr_immutable_id == "dcr-from-env"
        assert sink.stream_name == "Custom-FromEnv_CL"
