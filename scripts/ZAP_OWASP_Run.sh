#!/bin/bash

# Define variables for your target URL and config file
ZAP_TARGET_URL="http://infotechnologies.org"
ZAP_CONFIG_FILE="zapAlerts.config"

# Generate a default ZAP configuration file
# This runs the docker container to generate the file on the host.
# We use `--user $(id -u):$(id -g)` to ensure the files are created with
# the same user ID as the Cloud Build process.
docker run --rm -v $(pwd):/zap/wrk/:rw \
    --user $(id -u):$(id -g) \
    ghcr.io/zaproxy/zaproxy:stable \
    zap-baseline.py -t $ZAP_TARGET_URL -g /zap/wrk/$ZAP_CONFIG_FILE

# Edit the generated config file to ignore specific warnings.
# Example: ignore rule 10010 (No HttpOnly Flag) and 10011 (No Secure Flag)
# We can use `sed` to replace WARN with IGNORE.
# Note: You can also manually create this file and skip the generation step.
sed -i 's/10010\tWARN/10010\tIGNORE/' $ZAP_CONFIG_FILE
sed -i 's/10011\tWARN/10011\tIGNORE/' $ZAP_CONFIG_FILE

# Run the OWASP ZAP baseline scan with the custom config file.
# The volume mount makes the config file available to the container.
# We also use the same user to prevent permission issues.
docker run --rm -v $(pwd):/zap/wrk/:rw \
    --user $(id -u):$(id -g) \
    ghcr.io/zaproxy/zaproxy:stable \
    zap-baseline.py -t $ZAP_TARGET_URL -c /zap/wrk/$ZAP_CONFIG_FILE -T 5 -I

# The exit code from the ZAP scan will determine the build status.
# Exit code 0: Success.
# Exit code 1: FAIL alerts found.
# Exit code 2: WARN alerts found (if not ignored).
