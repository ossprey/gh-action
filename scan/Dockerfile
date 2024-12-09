# Use Python base image
FROM python:3.10-slim

# Install Poetry
RUN pip install --no-cache-dir poetry

# Copy files
COPY scan /app

# Set the working directory
WORKDIR /app/scan

# Install dependencies
RUN poetry install

# Set the entry point to the Python script
ENTRYPOINT ["poetry", "run", "python", "scan"]
