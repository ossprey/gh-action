# Use Python base image
FROM python:3.12-slim

# Install git
RUN apt-get update && apt-get install -y git

# Install Poetry
RUN pip install --no-cache-dir poetry==1.8.5

# Copy files
COPY . /app

# Set the working directory
WORKDIR /app

# Ensure virtual environments are created inside the project directory
RUN poetry config virtualenvs.in-project true

# Install dependencies explicitly for production (excluding dev dependencies)
RUN poetry install --no-dev --no-interaction --no-ansi
RUN poetry build

# Install the built package into the container
RUN pip install --no-cache-dir dist/*.whl

# Set the entry point to the Python script
ENTRYPOINT ["python", "-m", "scan"]
