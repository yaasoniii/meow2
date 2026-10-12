FROM ballerina/ballerina:2201.13.5 AS build
# The image defaults to a non-root user that cannot write to /app; only this
# throwaway build stage runs as root - the runtime stage below does not.
USER root
WORKDIR /app
COPY . .
RUN bal build

# The Kafka and MongoDB connectors need Java 21+
FROM eclipse-temurin:21-jre-jammy
WORKDIR /app
COPY --from=build /app/target/bin/*.jar ./admin_service.jar
COPY Config.toml ./Config.toml
EXPOSE 8087
ENTRYPOINT ["java", "-jar", "admin_service.jar"]
