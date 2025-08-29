# ------------ Build Stage ------------
FROM ballerina/ballerina:2201.12.9 AS builder

WORKDIR /app

# Copy project files
COPY . .

# Allow writing to target/ if needed
RUN chmod -R u+w /app || true

# Build the project (compiles main.bal and dependencies)
RUN bal build

# ------------ Runtime Stage ------------
FROM ballerina/ballerina:2201.12.9

WORKDIR /app

# Copy only the compiled jar
COPY --from=builder /app/target/bin/*.jar /app/app.jar

# Expose your HTTP/WebSocket port (only one for Railway)
EXPOSE 9092 9093

# Run the compiled Ballerina app
CMD ["bal", "run", "/app/app.jar"]
