# ------------ Build Stage ------------
FROM ballerina/ballerina:2201.12.9 as builder

WORKDIR /app

COPY . .

# Disable auto-updating Dependencies.toml (needed for Railway)
ENV BAL_CONFIG_DEP_UPDATER_ENABLED=false

# Build the project (no need for chmod, this avoids permission issues)
RUN bal build --offline --sticky


# ------------ Runtime Stage ------------
FROM ballerina/ballerina:2201.12.9

WORKDIR /app

# Copy the built .jar file only
COPY --from=builder /app/target/bin/*.jar /app/app.jar

# Expose only the HTTP/WebSocket ports
EXPOSE 9092
EXPOSE 9093

# Run the compiled jar
CMD ["bal", "run", "/app/app.jar"]
