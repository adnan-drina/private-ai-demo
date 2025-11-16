FROM registry.access.redhat.com/ubi9/python-39:latest

USER root

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY database_mcp_server.py .

RUN chown -R 1001:0 /app && chmod -R g=u /app

USER 1001

EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--timeout", "60", "database_mcp_server:app"]


