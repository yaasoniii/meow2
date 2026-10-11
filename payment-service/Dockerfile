FROM ballerina/ballerina:2201.13.5 AS build
WORKDIR /app
COPY . .
RUN bal build

# ballerinax/kafka and the Postgres driver ship native libraries built for Java 21,
# so the runtime image must be Java 21+ (an openjdk:17 base will fail to load them).
FROM eclipse-temurin:21-jre-jammy
WORKDIR /app
RUN useradd --system --create-home --shell /usr/sbin/nologin appuser
COPY --from=build /app/target/bin/*.jar ./payment_service.jar
COPY Config.toml ./Config.toml
USER appuser
EXPOSE 8084
ENTRYPOINT ["java", "-jar", "payment_service.jar"]
