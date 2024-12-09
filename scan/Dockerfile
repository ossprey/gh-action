# Use Python base image
FROM python:3.10-slim

# Install Poetry
RUN pip install --no-cache-dir poetry

# Set the working directory
WORKDIR /app

# Copy files
COPY scan /app

# Install dependencies
RUN poetry install --no-root

# Set the entry point to the Python script
WORKDIR /app/scan
ENTRYPOINT ["poetry", "run", "python", "scan"]
