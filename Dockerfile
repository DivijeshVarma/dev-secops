# Stage 1: Build the application dependencies
FROM python:3.8-slim-bullseye AS builder

WORKDIR /app
COPY requirements.txt .

# Install dependencies into a separate directory
RUN pip install --no-cache-dir --upgrade -r requirements.txt --target=/app/dependencies

# Stage 2: Create the final, minimal production image
# Using a distroless base image for maximum security
FROM gcr.io/distroless/python3-debian11

# Set up the working directory and user
WORKDIR /app
USER nonroot

# Copy the application code and dependencies from the builder stage
COPY --from=builder /app/dependencies /app/dependencies
COPY app.py .

# Add the dependencies directory to the Python path
ENV PYTHONPATH=/app/dependencies

# The command to run your application
CMD ["app.py"]
