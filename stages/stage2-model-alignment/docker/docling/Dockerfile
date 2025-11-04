# Docling REST API Service
# Pre-installed Docling image for fast startup
FROM registry.access.redhat.com/ubi9/python-311:latest

USER root

# Install system dependencies
RUN dnf install -y \
    gcc \
    g++ \
    poppler-utils \
    && dnf clean all

USER 1001

# Install Docling and dependencies
RUN pip install --no-cache-dir \
    docling \
    fastapi \
    uvicorn[standard] \
    python-multipart

# Copy the REST API wrapper
COPY app.py /opt/app-root/src/

EXPOSE 8080

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080", "--log-level", "info"]
