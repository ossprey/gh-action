# Use Python base image
FROM python:3.12-slim

# Install git
RUN apt-get update && apt-get install -y git

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

# Set environment variables to use the local virtual environment
ENV PATH="/app/.venv/bin:$PATH"
ENV PYTHONPATH="/app/.venv/lib/python3.12/site-packages:$PYTHONPATH"

# Set the entry point to the Python script
ENTRYPOINT ["poetry", "run", "python", "-m", "scan"]
