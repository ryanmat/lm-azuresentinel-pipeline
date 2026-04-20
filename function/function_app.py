"""
Description: Azure Function entry point for LM LogAlert ingestion.
Description: Session 1 skeleton - logs EH message receipt, Session 2 adds transform + Logs Ingestion.
"""
from __future__ import annotations

import json
import logging

import azure.functions as func

app = func.FunctionApp()


@app.event_hub_message_trigger(
    arg_name="event",
    event_hub_name="%EVENT_HUB_NAME%",
    connection="EventHubConnection",
    cardinality="one",
)
def process_lm_alerts(event: func.EventHubEvent) -> None:
    body = event.get_body().decode("utf-8", errors="replace")
    try:
        parsed = json.loads(body)
        logging.info(
            "LM alert received: id=%s type=%s severity=%s host=%s",
            parsed.get("alertId"),
            parsed.get("alertType"),
            parsed.get("severity"),
            parsed.get("deviceName"),
        )
    except json.JSONDecodeError:
        logging.warning("Non-JSON payload on EH (first 500 bytes): %r", body[:500])
