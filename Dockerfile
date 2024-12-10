# Use Python base image
FROM python:3.12-slim

# Install Poetry
RUN pip install --no-cache-dir poetry

# Copy files
COPY . /app

# Set the working directory
WORKDIR /app

# Ensure virtual environments are created inside the project directory
RUN poetry config virtualenvs.in-project true

# Install dependencies explicitly for production (excluding dev dependencies)
RUN poetry install --no-dev --no-interaction --no-ansi

# Debug: Check that requests is installed
RUN poetry run python -c "import requests; print(requests.__version__)"

# Set the entry point to the Python script
ENTRYPOINT ["poetry", "run", "python", "-m", "scan"]
