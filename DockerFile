# Use an official Java runtime as a parent image
FROM openjdk:17-jdk-slim AS build

# Set the working directory in the container
WORKDIR /app

# Copy the current directory contents into the container at /app
COPY  target/crone-0.0.1-SNAPSHOT.jar   /app/app.jar

 # Expose the port your application runs on (e.g., 8080)
 EXPOSE 9090


# Run the Java program
ENTRYPOINT ["java", "-jar", "/app/app.jar"]