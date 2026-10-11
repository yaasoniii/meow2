FROM ballerina/ballerina:2201.9.0 AS build
WORKDIR /app
COPY . .
RUN bal build -c payment_service.bal || bal build

FROM openjdk:17-jdk-slim
WORKDIR /app
COPY --from=build /app/target/bin/payment_service.jar .
COPY --from=build /app/Config.toml .
EXPOSE 8083
CMD ["java", "-jar", "payment_service.jar"]
