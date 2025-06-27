# Kiln OCR Processing Container
FROM python:3.11-slim

# Install system dependencies for OCR processing
RUN apt-get update && apt-get install -y \
    tesseract-ocr \
    tesseract-ocr-eng \
    libopencv-dev \
    python3-opencv \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements and install Python dependencies
COPY ./config/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy OCR processing scripts
COPY ./code/*.py /app/

# Set environment variables
ENV TESSDATA_PREFIX=/usr/share/tesseract-ocr/4.00/tessdata
ENV PYTHONPATH=/app
ENV KILN_DATA_PATH=/data
ENV LOG_PATH=/logs

# Create non-root user for security
RUN useradd -r -s /bin/false ocruser
USER ocruser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD python3 -c "import cv2, pytesseract; print('OCR container healthy')" || exit 1

# Default command
CMD ["python3", "frigate-ocr-integration.py"] 