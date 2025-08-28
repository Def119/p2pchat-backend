# FROM ballerina/ballerina:latest
# WORKDIR /app
# COPY . .
# RUN bal pack
# CMD ["bal", "run", "<your_service>"]

# Use official Ballerina image
FROM ballerina/ballerina:latest

# Set working directory
WORKDIR /app

# Copy your Ballerina project
COPY . .

# Build the Ballerina package
RUN bal build

# Railway provides PORT via env variable, so use that at runtime
# We will pass it into the Ballerina app using environment variable substitution
EXPOSE 9092 9093

# Run the built Ballerina binary
CMD ["bal", "run", "main.bal"]
