FROM dart AS build

RUN apt-get update && \
    apt-get install -y git

WORKDIR /app

COPY pubspec.* ./
COPY dartnissanconnect/ ./
RUN dart pub get

COPY . .
RUN dart pub get
RUN dart compile exe src/leaf_2_mqtt.dart -o src/leaf_2_mqtt

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/src/leaf_2_mqtt /app/bin/

CMD ["/app/bin/leaf_2_mqtt"]
