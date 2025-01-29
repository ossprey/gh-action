# Use Python base image
FROM python:3.12-slim

# Install git
RUN apt-get update && apt-get install -y git
RUN pip install git+https://github.com/ossprey/ossprey-python-client@v1.0.0

# Set the entry point to the Python script
ENTRYPOINT ["python", "-m", "scan"]
