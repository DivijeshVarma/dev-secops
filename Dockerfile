# Stage 1: Build a secure, minimal Nginx image
FROM nginx:1.27.0-alpine AS builder

# Stage 2: Create the final image with a non-root user
FROM alpine:3.19

# Install Nginx and other necessary packages
# Use apk's --no-cache flag to reduce image size
RUN apk add --no-cache nginx

# Create a non-root user and group
RUN addgroup -S nginx -G nginx

# Copy default Nginx configuration
COPY --from=builder /etc/nginx/nginx.conf /etc/nginx/nginx.conf

# Set the working directory
WORKDIR /var/www/html

# Change the user to the non-root user
USER nginx

# Expose the port Nginx will listen on
EXPOSE 8080

# The command to run Nginx
CMD ["nginx", "-g", "daemon off;"]
