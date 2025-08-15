# Stage 1: Builder
# Use a slim-bullseye base image for a smaller footprint
FROM python:3.8-slim-bullseye AS builder

# Install build dependencies if needed, and remove them in the final image
# This ensures a minimal final image
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Stage 2: Final Image
# Use a distroless base image for maximum security
# This image contains only your app and its runtime dependencies
FROM python:3.8-slim-bullseye

# Create a non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser
USER appuser

# Copy your application files and installed packages
WORKDIR /app
COPY --from=builder /app .

# Expose the correct port
EXPOSE 8080

# The command to run your application
CMD ["python", "app.py"]
