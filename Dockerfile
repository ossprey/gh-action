# Use Python base image
FROM python:3.12-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g yarn \
    && apt-get clean && rm -rf /var/lib/apt/lists/*


# Install Python Client
RUN pip install ossprey

# Set the entry point to the Python script
ENTRYPOINT ["python", "-m", "ossprey"]
