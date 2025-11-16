FROM registry.redhat.io/rhoai/odh-llama-stack-core-rhel9:0.0-1762357606

# Install the TrustyAI FMS Llama Stack provider ahead of time so the
# runtime no longer needs to pip install on every pod start.
# We keep it in a world-readable directory and extend PYTHONPATH
# plus LLAMA_STACK_EXTERNAL_PROVIDERS_DIR to match upstream docs.
USER root

ENV TRUSTYAI_PROVIDER_DIR=/opt/app-root/trustyai-provider

RUN mkdir -p "${TRUSTYAI_PROVIDER_DIR}" \
    && python3 -m pip install --no-cache-dir --upgrade \
         --target "${TRUSTYAI_PROVIDER_DIR}" \
         git+https://github.com/trustyai-explainability/llama-stack-provider-trustyai-fms.git \
    && chown -R 1001:0 "${TRUSTYAI_PROVIDER_DIR}" \
    && chmod -R g=u "${TRUSTYAI_PROVIDER_DIR}"

ENV PYTHONPATH="${TRUSTYAI_PROVIDER_DIR}:${PYTHONPATH}" \
    LLAMA_STACK_EXTERNAL_PROVIDERS_DIR="${TRUSTYAI_PROVIDER_DIR}/llama_stack_provider_trustyai_fms/providers.d"

USER 1001

