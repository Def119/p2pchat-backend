# Use Ballerina image (has bal CLI) as runtime too
FROM ballerina/ballerina:2201.12.9

# Set the working directory inside the container
WORKDIR /app

# Copy your project files into the container
COPY . .

# Optional: Ensure write permissions (in case bal needs to write deps)
RUN chmod -R u+w /app || true

# Expose any relevant ports (adjust these as per your app)
EXPOSE 9092
EXPOSE 9093

# Run the Ballerina source code
CMD ["bal", "run"]
