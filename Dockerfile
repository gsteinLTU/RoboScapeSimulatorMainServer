FROM nimlang/nim:latest-alpine-regular

RUN apk update && \
    apk add alpine-sdk

COPY . .

RUN nimble build -y

EXPOSE 5000

CMD ["./build/RoboScapeSimulatorMainServer"]