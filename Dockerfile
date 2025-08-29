FROM ballerina/ballerina:2201.12.9

WORKDIR /app

# Copy project files
COPY . .

# Set permissions for the /app directory
RUN chown -R 777 /app || true

# Expose the ports your app listens on
EXPOSE 9092
EXPOSE 9093

# Run as the ballerina user (default in Ballerina images)
USER ballerina

# Run the Ballerina package directly
CMD ["bal", "run"]