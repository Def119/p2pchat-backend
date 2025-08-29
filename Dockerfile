FROM ballerina/ballerina:2201.12.9

# Set working directory
WORKDIR /app

# Copy your Ballerina project
COPY . .

# Temporarily switch to root to fix permissions
USER root
RUN chmod -R u+w /app

# Switch back to default (non-root) user
USER ballerina

# Expose ports your app uses
EXPOSE 9092
EXPOSE 9093

# Run the Ballerina source
CMD ["bal", "run"]
