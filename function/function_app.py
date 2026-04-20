"""
Description: Azure Function entry point for LM LogAlert ingestion into Microsoft Sentinel.
Description: EH trigger parses LM webhook JSON, normalizes via src.transform, uploads via src.ingest.
"""
from __future__ import annotations

import json
import logging

import azure.functions as func

from src.ingest import LogsIngestionSink
from src.transform import transform

app = func.FunctionApp()

_sink: LogsIngestionSink | None = None


def _get_sink() -> LogsIngestionSink:
    global _sink
    if _sink is None:
        _sink = LogsIngestionSink()
    return _sink


@app.event_hub_message_trigger(
    arg_name="event",
    event_hub_name="%EVENT_HUB_NAME%",
    connection="EventHubConnection",
    cardinality="one",
)
def process_lm_alerts(event: func.EventHubEvent) -> None:
    body = event.get_body().decode("utf-8", errors="replace")

    try:
        raw_payload = json.loads(body)
    except json.JSONDecodeError as exc:
        logging.error("Non-JSON payload on EH; dropping. Body[:500]=%r err=%s", body[:500], exc)
        return

    try:
        normalized = transform(raw_payload)
    except Exception as exc:
        logging.exception("Failed to transform LM alert: %s", exc)
        return

    logging.info(
        "LM alert normalized: id=%s type=%s severity=%s status=%s device=%s",
        normalized.LmAlertId,
        normalized.AlertType,
        normalized.Severity,
        normalized.Status,
        normalized.DeviceName,
    )

    _get_sink().send([normalized.to_dcr_row()])
