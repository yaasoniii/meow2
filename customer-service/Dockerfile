FROM ballerina/ballerina:2201.13.5 AS build
# The image defaults to a non-root user that cannot write to /app; only this
# throwaway build stage runs as root - the runtime stage below does not.
USER root
WORKDIR /app
COPY . .
RUN bal build

# ballerinax/mongodb and ballerinax/kafka ship native libraries built for Java 21,
# so the runtime image must be Java 21+ (an openjdk:17 base will fail to load them).
FROM eclipse-temurin:21-jre-jammy
WORKDIR /app
RUN useradd --system --create-home --shell /usr/sbin/nologin appuser
COPY --from=build /app/target/bin/*.jar ./customer_service.jar
COPY Config.toml ./Config.toml
USER appuser
EXPOSE 8082
ENTRYPOINT ["java", "-jar", "customer_service.jar"]
