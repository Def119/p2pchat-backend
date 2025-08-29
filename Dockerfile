FROM ballerina/ballerina:2201.12.7

WORKDIR /app

# Copy precompiled artifacts
COPY target/bin/p2pchat_backend.jar .
COPY Dependencies.toml .

# Expose the ports your app listens on
EXPOSE 9092
EXPOSE 9093

# Run as the ballerina user
USER ballerina

# Run the precompiled JAR
CMD ["bal", "run", "p2pchat_backend.jar"]