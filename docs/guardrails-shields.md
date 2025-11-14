# Guardrails Shields in the Llama Stack Playground

## Overview

The Llama Stack playground now exposes TrustyAI shields in both the Chat and RAG tabs. You can flip them on or off from the sidebar to demonstrate baseline behaviour versus protected workflows.

When the toggle is enabled the playground:

- Screens the user prompt (and the RAG-augmented prompt when applicable) **before** an inference call.
- Optionally screens the assistant response **after** inference and suppresses it if a violation is detected.
- Surfaces the detector output (violation metadata, message) instead of the model response when blocked.

Guardrail configuration is managed centrally by the TrustyAI Guardrails Orchestrator and mirrored into the Llama Stack `run.yaml`.

## Available Shields

| Shield ID            | Type     | Description |
|----------------------|----------|-------------|
| `regex_guardrail`    | Content  | Regex-based PII detection (email, SSN, credit card, US phone numbers, basic two-word names). |
| `toxicity_guardrail` | Content  | ML toxicity detector based on the `ibm-granite/granite-guardian-hap-38m` Hugging Face model. |

Both shields are delivered by the TrustyAI FMS provider (`trustyai_fms`) that points to the Guardrails Orchestrator.

## Adding a New Shield

1. **Register or deploy a detector**
   - Use the [TrustyAI detector collection repo](https://github.com/opendatahub-io/guardrails-detectors) as the source.
   - For built-in regex/file validators no extra deployment is required.
   - For ML detectors (e.g. Hugging Face, LLM Judge) deploy the detector as a service. In this repository the Hugging Face detector build and deployment manifests live under `gitops/stage02-model-alignment/guardrails/`.

2. **Expose the detector in the Guardrails Orchestrator config**
   - Edit `guardrails-configmap.yaml` and add a new entry under `detectors` with the `service` host/port and any `detector_params` the detector expects (e.g. `detector_id`).

3. **Create a shield in Llama Stack**
   - Update `gitops/stage02-model-alignment/llama-stack/configmap.yaml`:
     - Add the detector name and parameters under `providers.safety[].config.shields`.
     - Append a new entry to the top-level `shields` list so the shield appears in the UI dropdown.

4. **Reference the shield in the UI**
   - The playground auto-discovers shield IDs from the `llama_stack` API. No UI change is required—after applying the new configuration and restarting the `llama-stack-playground` deployment the shield will appear in the dropdown.

5. **Apply and restart**
   - Run `oc apply -k gitops/stage02-model-alignment/guardrails` to update the orchestrator and detector resources.
   - Run `oc apply -k gitops/stage02-model-alignment/llama-stack` followed by `oc rollout restart deployment/llama-stack-playground` to refresh the playground.

## Demonstration Tips

- Keep the guardrail toggles off to show the raw model output, then enable them to highlight the blocked response.
- The RAG view offers separate toggles to screen the user prompt, the RAG-augmented prompt, and the assistant response—handy to illustrate the layered protection story.
- Use the example PII prompt (`Jamie… email… SSN… credit card…`) to trigger `regex_guardrail`, and a toxic phrase (e.g. “I hate you…”) to demonstrate the Hugging Face toxicity shield once the detector pod is up.


