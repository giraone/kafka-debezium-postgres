# Setup for Postgres, Debezium and Kafka Connect

## Links 

- https://docs.confluent.io/current/installation/configuration/connect/source-connect-configs.html
- https://docs.confluent.io/current/installation/configuration/connect/sink-connect-configs.html
- https://debezium.io/documentation/reference/1.0/connectors/postgresql.html#connector-properties
- https://debezium.io/blog/2017/09/25/streaming-to-another-database/
- https://debezium.io/documentation/faq/
- https://docs.confluent.io/current/connect/kafka-connect-http/index.html
- [Outbox Event Router Configuration](https://debezium.io/documentation/reference/configuration/outbox-event-router.html#_configuration)

- https://thorben-janssen.com/outbox-pattern-hibernate/
- https://thorben-janssen.com/outbox-pattern-with-cdc-and-debezium/

- [Support Outbox SMT as part of Debezium core](https://issues.redhat.com/browse/DBZ-1169)

- `io.debezium.connector.postgresql.PostgresConnector vs io.confluent.connect.jdbc.JdbcSourceConnector`

## Docker Setup

See [docker-compose.yml](kafka-debezium-postgres-5.5-11/docker-compose.yml).

- Run [volumes-setup.sh](kafka-debezium-postgres-5.5-11/volumes-setup.sh).
- Run `docker-compose up -d`
- Check logs, e.g. `docker logs connect`
- In case of a reset, run `sudo volumes-clean.sh` - See [volumes-clean.sh](kafka-debezium-postgres-5.5-11/volumes-clean.sh).

## Setup Debezium Connectors with Kafka Connect

### (1) Manual installation

- See https://www.confluent.io/hub/debezium/debezium-connector-postgresql.
- Download ZIP file
- Extract ZIP file
- Copy all JARs from `lib` directory to a directory within `data/connect/plugins` (= `CONNECT_PLUGIN_PATH`), e.g. `debezium-connector-postgresql-1.2.1`.
- Restart *connect* container: `docker restart connect`

### (2) Confluent-Hub installation

```
$ docker-compose exec connect /bin/bash
root@connect:/# confluent-hub install debezium/debezium-connector-postgresql:1.2.1
The component can be installed in any of the following Confluent Platform installations: 
  1. / (installed rpm/deb package) 
  2. / (where this tool is installed) 
Choose one of these to continue the installation (1-2): 2
Do you want to install this into /usr/share/confluent-hub-components? (yN) y

 
Component's license: 
Apache 2.0 
https://github.com/debezium/debezium/blob/master/LICENSE.txt 
I agree to the software license agreement (yN) y

You are about to install 'debezium-connector-postgresql' from Debezium Community, as published on Confluent Hub. 
Do you want to continue? (yN) y

Downloading component Debezium PostgreSQL CDC Connector 1.2.1, provided by Debezium Community from Confluent Hub and installing into /usr/share/confluent-hub-components 
Detected Worker's configs: 
  1. Standard: /etc/kafka/connect-distributed.properties 
  2. Standard: /etc/kafka/connect-standalone.properties 
  3. Standard: /etc/schema-registry/connect-avro-distributed.properties 
  4. Standard: /etc/schema-registry/connect-avro-standalone.properties 
  5. Used by Connect process with PID : /etc/kafka-connect/kafka-connect.properties 
Do you want to update all detected configs? (yN) y

Adding installation directory to plugin path in the following files: 
  /etc/kafka/connect-distributed.properties 
  /etc/kafka/connect-standalone.properties 
  /etc/schema-registry/connect-avro-distributed.properties 
  /etc/schema-registry/connect-avro-standalone.properties 
  /etc/kafka-connect/kafka-connect.properties 
 
Completed 
```

**Extra work, because the ZIP file does not have the JARs in the root folder and is not recognized:

```
root@connect:/# cd /usr/share/confluent-hub-components
root@connect:/usr/share/confluent-hub-components# ls
confluentinc-kafka-connect-gcs	debezium-debezium-connector-postgresql
root@connect:/usr/share/confluent-hub-components# mv debezium-debezium-connector-postgresql/lib debezium-connector-postgresql-1.2.1
root@connect:/usr/share/confluent-hub-components# rm -rf debezium-debezium-connector-postgresql
```

Now you have to add `/usr/share/confluent-hub-components/debezium-debezium-connector-postgresql` to the `CONNECT_PLUGIN_PATH` environment variable in [docker-compose.yml](kafka-debezium-postgres-5.5-11/docker-compose.yml) and restart the *connect* container.

### Check that connector can be used:

```
curl -X GET -H "Accept: application/json" "http://localhost:8083/connector-plugins" | jq
```

## Setup

```
curl -X GET -H "Accept: application/json" "http://localhost:8083/connector-plugins"
[
 {"class":"io.debezium.connector.postgresql.PostgresConnector","type":"source","version":"1.0.0.Final"},
 {"class":"org.apache.kafka.connect.file.FileStreamSinkConnector","type":"sink","version":"5.3.1-ccs"},
 {"class":"org.apache.kafka.connect.file.FileStreamSourceConnector","type":"source","version":"5.3.1-ccs"}
] 

curl -X GET -H "Accept: application/json" "http://localhost:8083/connectors"
[]

curl -X POST -H "Content-Type: application/json" -d @postgres-source-outbox.json "http://localhost:8083/connectors"
curl -X POST -H "Content-Type: application/json" -d @postgres-source-route.json "http://localhost:8083/connectors"

curl -X GET -H "Accept: application/json" "http://localhost:8083/connectors/source-postgres-outbox"
curl -X GET -H "Accept: application/json" "http://localhost:8083/connectors/source-postgres-route"

curl -s localhost:8083/connectors/source-postgres-outbox/status

curl -s localhost:8083/connectors/source-postgres-outbox/tasks
[{"id":{"connector":"source-pms-postgres","task":0},"config":
{"connector.class":"io.debezium.connector.postgresql.PostgresConnector","database.user":"user","database.dbname":"user",
"task.class":"io.debezium.connector.postgresql.PostgresConnectorTask","database.hostname":"postgres-source",
"database.password":"password","name":"source-pms-postgres","database.server.name":"postgres-source","database.port":"5432",
"table.whitelist":"company"}}

curl -s localhost:8083/connectors/sink-pms-postgres/tasks
[{"id":{"connector":"sink-pms-postgres","task":0},"config":{"connector.class":"io.confluent.connect.jdbc.JdbcSinkConnector",
"connection.password":"password","tasks.max":"1",
"topics":"postgres-source.public.jhi_user,postgres-source.public.jhi_user_authority,postgres-source.public.company,postgres-source.public.employee,postgres-source.public.company_user,postgres-source.public.employee_name",
"value.converter.schema.registry.url":"http://schema-registry:8081","auto.evolve":"true",
"task.class":"io.confluent.connect.jdbc.sink.JdbcSinkTask","connection.user":"user","name":"sink-pms-postgres",
"auto.create":"true","connection.url":"jdbc:postgresql://postgres-target:5433/user",
"value.converter":"io.confluent.connect.avro.AvroConverter","insert.mode":"upsert",
"key.converter":"io.confluent.connect.avro.AvroConverter","key.converter.schema.registry.url":"http://schema-registry:8081",
"pk.mode":"record_key","pk.fields":"id"}}]

curl -X DELETE localhost:8083/connectors/source-postgres-outbox

curl -X POST localhost:8083/connectors/source-postgres-outbox/restart
curl -X PUT localhost:8083/connectors/source-postgres-outbox/pause
curl -X PUT localhost:8083/connectors/source-postgres-outbox/resume

```

## In ACTION

```
docker-compose exec tools /bin/bash
kafka-topics --bootstrap-server kafka-1:9092 --list
kafka-topics --bootstrap-server kafka-1:9092 --create --replication-factor 1 --partitions 8 --topic private.test.pws.loon.outbox

docker-compose exec postgres-source bash -c 'psql -d user -U user'

kafka-console-consumer \
    --bootstrap-server kafka-1:9092 \
    --from-beginning \
    --property print.key=true \
    --topic private.test.pws.loon.outbox

### Output

"Jim"	{"payload":"{ \"name\": \"Jim\", \"email\": \"jim@gmail.com\" }","added":"2020-08-03T21:18:21.120034Z"}
"Jack"	{"payload":"{\"name\": \"Jack\", \"email\": \"jack@gmail.com\"}","meta.added":1596492819496104}
"Jack"	{"payload":"{\"name\": \"Jack\", \"email\": \"jack@gmail.com\"}","meta.added":"2020-08-03T22:16:17.332316Z"}


# Ohne AVRO
kafka-console-consumer --bootstrap-server kafka-1:9092 --group console-group-1 \
 --topic postgres-source.public.company --from-beginning
{"before":null,"after":{"id":1051,"external_id":"test-0001","name":"Yosemite Tree","postal_code":"94542","city":"Ansbach","street_address":"Göthestr. 18"},"source":{"version":"1.0.0.Final","connector":"postgresql","name":"postgres-source","ts_ms":1579535197081,"snapshot":"true","db":"user","schema":"public","table":"company","txId":607,"lsn":24029856,"xmin":null},"op":"r","ts_ms":1579535197084}
{"before":null,"after":{"id":1101,"external_id":"test-0002","name":"Test-Company 0002","postal_code":"91052","city":"Erlangen","street_address":"Am Weg 1"},"source":{"version":"1.0.0.Final","connector":"postgresql","name":"postgres-source","ts_ms":1579535197087,"snapshot":"true","db":"user","schema":"public","table":"company","txId":607,"lsn":24029856,"xmin":null},"op":"r","ts_ms":1579535197087}
{"before":null,"after":{"id":1051,"external_id":"test-0001","name":"Test-Company 0001","postal_code":"94542","city":"Ansbach","street_address":"Göthestr. 18"},"source":{"version":"1.0.0.Final","connector":"postgresql","name":"postgres-source","ts_ms":1579535426073,"snapshot":"false","db":"user","schema":"public","table":"company","txId":611,"lsn":24032256,"xmin":null},"op":"u","ts_ms":1579535426087}
{"before":null,"after":{"id":1051,"external_id":"test-0001","name":"Test-Company 0001","postal_code":"94542","city":"Ansbach","street_address":"Göthestr. 18"},"source":{"version":"1.0.0.Final","connector":"postgresql","name":"postgres-source","ts_ms":1579554376209,"snapshot":"false","db":"user","schema":"public","table":"company","txId":589,"lsn":24065488,"xmin":null},"op":"c","ts_ms":1579554376304}

# Mit AVRO und Topic-Name-Transformation
kafka-avro-console-consumer --bootstrap-server kafka-1:9092 --group console-group-1 \
 --property "schema.registry.url=http://schema-registry:8081" \
 --topic company --from-beginning

```

## MISC

- Connect ohne AVRO

```
key.converter.schemas.enable=false
value.converter.schemas.enable=false
key.converter=org.apache.kafka.connect.storage.StringConverter
value.converter=org.apache.kafka.connect.json.JsonConverter
```

- Outbox customizing
  - Ohne Configuration entsteht 'outbox.event.student' Topic
  - `"transforms.outbox.table.field.event.timestamp": "added"  ==> Erwartet int64

```

        "transforms": "outbox",
        "transforms.outbox.type": "io.debezium.transforms.outbox.EventRouter",
        "transforms.outbox.route.topic.replacement": "test.${routedByValue}",
        "transforms.outbox.table.fields.additional.placement": "major_version:envelope:major_version",
        "transforms.outbox.table.fields.additional.placement": "minor_version:envelope:minor_version",
        "transforms.outbox.table.fields.additional.placement": "type:header:eventType",
        "transforms.outbox.table.fields.additional.placement": "added:envelope:added"


"transforms.outbox.route.topic.replacement": "student.events",
"transforms.outbox.table.fields.additional.placement" : "aggregateid:envelope:id"
"transforms.outbox.table.field.event.timestamp": "timestamp"
```

- RegexRouter customizing (Regex is base database.schema.table)
```
"transforms.renameTopic.type": "org.apache.kafka.connect.transforms.RegexRouter",
"transforms.renameTopic.regex": "(.*)",
"transforms.renameTopic.replacement": "user.$1.events"

"transforms": "route",
"transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
"transforms.route.regex": "([^.]+)\\.([^.]+)\\.([^.]+)",
"transforms.route.replacement": "$3"
```

- PK
```
    "pk.fields": "id",
    "pk.fields": "id,itemId",
    "pk.mode": "record_key",
    "pk.mode":"none",
```
