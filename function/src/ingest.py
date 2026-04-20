"""
Description: Logs Ingestion API client wrapper using Managed Identity.
Description: Sends normalized alert rows to a DCE + DCR that fronts LogicMonitorAlerts_CL.
"""
from __future__ import annotations

import logging
import os

from azure.identity import ManagedIdentityCredential
from azure.monitor.ingestion import LogsIngestionClient

_log = logging.getLogger(__name__)


class LogsIngestionSink:
    """Thin wrapper around azure-monitor-ingestion that reads endpoint and DCR config from env."""

    def __init__(
        self,
        endpoint: str | None = None,
        dcr_immutable_id: str | None = None,
        stream_name: str | None = None,
    ):
        self.endpoint = endpoint or os.environ["DCE_ENDPOINT"]
        self.dcr_immutable_id = dcr_immutable_id or os.environ["DCR_IMMUTABLE_ID"]
        self.stream_name = stream_name or os.environ["DCR_STREAM_NAME"]
        self._client: LogsIngestionClient | None = None

    @property
    def client(self) -> LogsIngestionClient:
        if self._client is None:
            credential = ManagedIdentityCredential()
            self._client = LogsIngestionClient(
                endpoint=self.endpoint,
                credential=credential,
                logging_enable=False,
            )
        return self._client

    def send(self, rows: list[dict]) -> None:
        """Upload a batch of rows to the DCR stream. Raises on failure so the EH trigger can retry."""
        if not rows:
            return
        _log.info(
            "Uploading %d rows to stream=%s dcr=%s",
            len(rows),
            self.stream_name,
            self.dcr_immutable_id,
        )
        self.client.upload(
            rule_id=self.dcr_immutable_id,
            stream_name=self.stream_name,
            logs=rows,
        )
