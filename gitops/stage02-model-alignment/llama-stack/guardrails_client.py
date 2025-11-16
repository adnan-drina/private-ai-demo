import os
from typing import Any, Dict, Iterable, List, Mapping, Optional

import requests


DEFAULT_GUARDRAILS_URL = os.environ.get(
    "GUARDRAILS_BASE_URL",
    "https://guardrails-route-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com",
)

SHIELD_DEFINITIONS: Dict[str, Dict[str, Any]] = {
    "regex_guardrail": {
        "label": "Regex-based PII",
        "detectors": {
            "regex": {
                "regex": [
                    "email",
                    "ssn",
                    "credit_card",
                    "us-phone-number",
                ]
            }
        },
    },
    "toxicity_guardrail": {
        "label": "Toxicity (HAP)",
        "detectors": {
            "hf_toxicity": {
                "detector_id": "hap",
            }
        },
    },
}


def _to_bool(value: Optional[str], default: bool = True) -> bool:
    if value is None:
        return default
    return value.strip().lower() not in {"0", "false", "no"}


class GuardrailClient:
    """Thin wrapper around the Guardrails Orchestrator REST API."""

    def __init__(
        self,
        base_url: Optional[str] = None,
        *,
        timeout: Optional[float] = None,
        verify: Optional[bool] = None,
    ) -> None:
        self.base_url = (base_url or DEFAULT_GUARDRAILS_URL).rstrip("/")
        self.timeout = timeout or float(os.environ.get("GUARDRAILS_TIMEOUT", "20"))
        verify_env = os.environ.get("GUARDRAILS_VERIFY_TLS")
        self.verify = verify if verify is not None else _to_bool(verify_env, default=True)
        self._session = requests.Session()

    def _endpoint(self, path: str) -> str:
        return f"{self.base_url}{path}"

    def detect_content(self, shield_id: str, text: str) -> List[Mapping[str, Any]]:
        shield = SHIELD_DEFINITIONS.get(shield_id)
        if not shield:
            raise ValueError(f"Unknown guardrail shield '{shield_id}'")
        payload = {
            "detectors": shield["detectors"],
            "content": text,
        }
        response = self._session.post(
            self._endpoint("/api/v2/text/detection/content"),
            json=payload,
            timeout=self.timeout,
            verify=self.verify,
        )
        response.raise_for_status()
        data = response.json()
        return data.get("detections", [])

    @staticmethod
    def build_violation(
        shield_id: str,
        detections: Iterable[Mapping[str, Any]],
        source_text: str,
    ) -> Dict[str, Any]:
        detections = list(detections)
        detection_count = len(detections)
        summary = {
            "total_messages": 1,
            "processed_messages": 1,
            "skipped_messages": 0,
            "messages_with_violations": 1,
            "messages_passed": 0,
            "message_fail_rate": 1.0,
            "message_pass_rate": 0.0,
            "total_detections": detection_count,
            "detector_breakdown": {
                "active_detectors": len({d.get("detector_id") for d in detections}),
                "total_checks_performed": 1,
                "total_violations_found": detection_count,
                "violations_per_message": detection_count,
            },
        }
        results = [
            {
                "message_index": 0,
                "text": detection.get("text") or source_text,
                "status": "violation",
                "score": detection.get("score"),
                "detection_type": detection.get("detection_type"),
                "individual_detector_results": [
                    {
                        "detector_id": detection.get("detector_id"),
                        "status": "violation",
                        "score": detection.get("score"),
                        "detection_type": detection.get("detection_type"),
                    }
                ],
            }
            for detection in detections
        ]
        return {
            "violation_level": "error",
            "user_message": (
                f"Content violation detected by shield {shield_id} "
                f"({detection_count} detection(s) reported)."
            ),
            "metadata": {
                "status": "violation",
                "shield_id": shield_id,
                "summary": summary,
                "results": results,
            },
        }


