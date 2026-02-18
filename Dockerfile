# ===============================
# Stage 1: Build the Application
# ===============================
FROM eclipse-temurin:17-jdk-jammy AS builder

WORKDIR /app

# 1. Copy Maven wrapper and build files first to leverage Docker layer caching
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./

# 2. Make the wrapper executable (linux only)
RUN chmod +x mvnw

# 3. Download dependencies (this step is cached if pom.xml doesn't change)
# We run a dependency resolution step here to speed up future builds
RUN ./mvnw dependency:go-offline

# 4. Copy the source code
COPY src ./src

# 5. Package the application (skipping tests to speed up the build)
RUN ./mvnw package -DskipTests

# ===============================
# Stage 2: Run the Application
# ===============================
FROM eclipse-temurin:17-jre-jammy

WORKDIR /app

# 6. Copy the JAR file from the builder stage
# The wildcard *.jar ensures we grab the jar regardless of version number
COPY --from=builder /app/target/*.jar app.jar

# 7. Expose the default Spring Boot port
EXPOSE 8080

# 8. Define the command to run the app
ENTRYPOINT ["java", "-jar", "app.jar"]