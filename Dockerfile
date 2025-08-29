# ------------ Build Stage ------------
FROM ballerina/ballerina:2201.12.9 as builder

WORKDIR /app

COPY . .

# Allow write permission just in case
RUN chmod -R u+w /app || true

# Prevent writing to Dependencies.toml
ENV BAL_CONFIG_DEP_UPDATER_ENABLED=false

# Build project (will NOT write to Dependencies.toml now)
RUN bal build

# ------------ Runtime Stage ------------
FROM ballerina/ballerina:2201.12.9

WORKDIR /app

COPY --from=builder /app/target/bin/*.jar /app/app.jar

EXPOSE 9092 9093

CMD ["bal", "run", "/app/app.jar"]
