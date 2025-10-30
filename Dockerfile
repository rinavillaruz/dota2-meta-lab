# Multi-stage Dockerfile for Dota2 Meta Lab

# =============================================================================
# Stage 1: Data Fetcher
# =============================================================================
FROM python:3.11-slim AS data-fetcher

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy data fetching script
COPY fetch_opendota_data.py .
COPY src/ ./src/

# This stage can be used to fetch data
ENTRYPOINT ["python", "fetch_opendota_data.py"]


# =============================================================================
# Stage 2: Model Trainer
# =============================================================================
FROM tensorflow/tensorflow:latest AS trainer

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy training scripts
COPY train_model.py .
COPY src/ ./src/

# Set environment variables
ENV DATA_DIR=/data/training
ENV MODEL_DIR=/models
ENV EPOCHS=50
ENV BATCH_SIZE=32

# This stage trains the model
ENTRYPOINT ["python", "train_model.py"]


# =============================================================================
# Stage 3: API Server (Main)
# =============================================================================
FROM python:3.11-slim AS api

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/ ./src/
COPY api/ ./api/

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD python -c "import requests; requests.get('http://localhost:8080/health')"

# Run API server
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "4", "--timeout", "120", "api.app:app"]


# =============================================================================
# Stage 4: Development
# =============================================================================
FROM python:3.11-slim AS development

WORKDIR /app

# Install development dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir jupyter notebook ipython

# Copy all code
COPY . .

# Expose ports for Jupyter and API
EXPOSE 8080 8888

# Development mode - start Jupyter by default
CMD ["jupyter", "notebook", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--allow-root"]