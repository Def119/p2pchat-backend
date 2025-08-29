FROM ballerina/ballerina:2201.12.9

WORKDIR /app

COPY . .

# Expose the ports your app listens on
EXPOSE 9092
EXPOSE 9093

# Run the Ballerina package directly
CMD ["bal", "run", "--offline", "--sticky", "."]
