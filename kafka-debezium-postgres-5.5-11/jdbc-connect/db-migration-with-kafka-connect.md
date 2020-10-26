# Database migration with Kafka Connect


This is a proof-of-concept, how one can migrate database values from one database to another using Kafka Connect and
its JDBC source and sink connector as a ETL tool. The basic use-case is migrating values from one microservice database to
another microservice database without writing much code.

## Setup

I am using *docker-compose* with Kafka, Kafka-Connect, ... and two Postgres-Databases. The full `docker-compose.yml` is shown below at the end.

Both databases contain a *student* table defined by:

```sql
CREATE TABLE public.student
(
    name character varying(255),
    email character varying(255),
    modified TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT student_pkey PRIMARY KEY (name)
);
```

The source database is filled with:

```sql
INSERT INTO public.student(NAME, EMAIL) VALUES('Jack','jack@gmail.com');
INSERT INTO public.student(NAME, EMAIL) VALUES('Jim','jim@gmail.com');
INSERT INTO public.student(NAME, EMAIL) VALUES('Peter','peter@gmail.com');
```

The resulting table content using `SELECT * FROM public.student` is

```csv
"name","email","modified"
"Jack","jack@gmail.com","2020-10-26 06:00:12.438026+00"
"Jim","jim@gmail.com","2020-10-26 06:00:12.438352+00"
"Peter","peter@gmail.com","2020-10-26 06:00:12.438413+00"
```

The target database is filled with record that have the same primary key (`name`) and an empty `email` column:

```sql
INSERT INTO public.student(NAME, EMAIL) VALUES('Jack','-');
INSERT INTO public.student(NAME, EMAIL) VALUES('Jim','-');
INSERT INTO public.student(NAME, EMAIL) VALUES('Peter','-');
```

The resulting table content using `SELECT * FROM public.student` is

```csv
"name","email","modified"
"Jack","-","2020-10-26 06:02:21.072779+00"
"Jim","-","2020-10-26 06:02:21.073043+00"
"Peter","-","2020-10-26 06:02:21.073101+00"
```

The goal is, that after a migration, all column values for `email` are transferred from the source to the target database
without changing other column values:

```csv
"name","email","modified"
"Jack","jack@gmail.com","2020-10-26 06:02:21.072779+00"
"Jim","jim@gmail.com","2020-10-26 06:02:21.073043+00"
"Peter","peter@gmail.com","2020-10-26 06:02:21.073101+00"
```

### Kafka Connect Configurations

The source connector configuration is:

```json
{
  "name": "jdbc-source",
  "config": {
    "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
    "tasks.max": "1",
    "poll.interval.ms": 100000000,
    
    "connection.url": "jdbc:postgresql://postgres-source:5432/user",
    "connection.user": "user",
    "connection.password": "password",

    "value.converter":"org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "true",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "key.converter.schemas.enable": "false",

    "mode": "bulk",
    "schema.pattern": "public",
    "table.whitelist": "student",

    "transforms": "dropTopicPrefix,valueToKey,extractKey",
    "topic.prefix": "prefix-",
    "transforms.dropTopicPrefix.type": "org.apache.kafka.connect.transforms.RegexRouter",
    "transforms.dropTopicPrefix.regex": "prefix-(.*)",
    "transforms.dropTopicPrefix.replacement": "bulk.student",
    "transforms.valueToKey.type": "org.apache.kafka.connect.transforms.ValueToKey",
    "transforms.valueToKey.fields": "name",
    "transforms.extractKey.type": "org.apache.kafka.connect.transforms.ExtractField$Key",
    "transforms.extractKey.field": "name"
  }
}
```

The sink/target connector configuration is:

```json
{
  "name": "jdbc-sink",
  "config": {
    "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
    "tasks.max": "1",

    "connection.url": "jdbc:postgresql://postgres-target:5432/user",
    "connection.user": "user",
    "connection.password": "password",

    "value.converter":"org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "true",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "key.converter.schemas.enable": "false",

    "topics": "bulk.student",

    "insert.mode": "update",
    "batch.size": "1",
    "pk.mode": "record_key",

    "table.name.format": "student",
    "pk.fields": "name",
    "fields.whitelist": "name,email"
  }
}
```

### Docker-Compose

```yaml
version: "3.5"
services:
  zk-1:
    image: confluentinc/cp-zookeeper:5.5.1
    hostname: zk-1
    ports:
      - "2181:2181"
    container_name: zk-1
    volumes:
      - ./data/zk-1/log:/var/lib/zookeeper/log
      - ./data/zk-1/data:/var/lib/zookeeper/data
    networks:
      - confluent
    environment:
      ZOOKEEPER_SERVER_ID: 1
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
      ZOOKEEPER_INIT_LIMIT: 5
      ZOOKEEPER_SYNC_LIMIT: 2
      ZOOKEEPER_SERVERS: "zk-1:2888:3888"

  kafka-1:
    image: confluentinc/cp-enterprise-kafka:5.5.1
    hostname: kafka-1
    ports:
      - "9092:9092"
    container_name: kafka-1
    networks:
      - confluent
    volumes:
      - ./data/kafka-1/data:/var/lib/kafka/data
    environment:
      KAFKA_BROKER_ID: 101
      KAFKA_ZOOKEEPER_CONNECT: "zk-1:2181"
      KAFKA_ADVERTISED_LISTENERS: "PLAINTEXT://kafka-1:9092"
      KAFKA_AUTO_LEADER_REBALANCE_ENABLE: "true"
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"
      KAFKA_DELETE_TOPIC_ENABLE: "true"
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_LOG4J_LOGGERS: "kafka.authorizer.logger=DEBUG,kafka.controller=INFO,kafka.producer.async.DefaultEventHandler=INFO,state.change.logger=INFO"
      # Needs more setup
      # KAFKA_METRIC_REPORTERS: "io.confluent.metrics.reporter.ConfluentMetricsReporter"
      CONFLUENT_SUPPORT_METRICS_ENABLE: "false"
      # CONFLUENT_METRICS_REPORTER_TOPIC_REPLICAS: 1
      # CONFLUENT_METRICS_REPORTER_BOOTSTRAP_SERVERS: "kafka-1:9092"
      # CONFLUENT_METRICS_REPORTER_SECURITY_PROTOCOL: "SASL_PLAINTEXT"
      # CONFLUENT_METRICS_REPORTER_SASL_MECHAISM: "PLAIN"

  schema-registry:
    image: confluentinc/cp-schema-registry:5.5.1
    hostname: schema-registry
    container_name: schema-registry
    ports:
      - "8081:8081"
    networks:
      - confluent
    environment:
      SCHEMA_REGISTRY_HOST_NAME: schema-registry
      SCHEMA_REGISTRY_KAFKASTORE_CONNECTION_URL: "zk-1:2181"
      SCHEMA_REGISTRY_LISTENERS: http://schema-registry:8081

  connect:
    image: confluentinc/cp-kafka-connect:5.5.1
    hostname: connect
    container_name: connect
    ports:
      - "8083:8083"
    volumes:
      - ./data/connect/data:/data
      - ./data/connect/plugins:/plugins
    networks:
      - confluent
    environment:
      CONNECT_PRODUCER_INTERCEPTOR_CLASSES: io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor
      CONNECT_CONSUMER_INTERCEPTOR_CLASSES: io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor
      CONNECT_BOOTSTRAP_SERVERS: kafka-1:9092
      CONNECT_REST_PORT: 8083
      CONNECT_GROUP_ID: "connect"
      CONNECT_CONFIG_STORAGE_TOPIC: "connect-config"
      CONNECT_OFFSET_STORAGE_TOPIC: "connect-offsets"
      CONNECT_STATUS_STORAGE_TOPIC: "connect-status"
      CONNECT_REPLICATION_FACTOR: 1
      CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_STATUS_STORAGE_REPLICATION_FACTOR: 1
      # We do not want AVRO
      #CONNECT_KEY_CONVERTER: "io.confluent.connect.avro.AvroConverter"
      #CONNECT_VALUE_CONVERTER: "io.confluent.connect.avro.AvroConverter"
      # But JSON
      CONNECT_KEY_CONVERTER: "org.apache.kafka.connect.json.JsonConverter"
      CONNECT_VALUE_CONVERTER: "org.apache.kafka.connect.json.JsonConverter"
      # But no JSON schema within the events itself
      CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE: "false"
      CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE: "false"
      CONNECT_KEY_CONVERTER_SCHEMA_REGISTRY_URL: "http://schema-registry:8081"
      CONNECT_VALUE_CONVERTER_SCHEMA_REGISTRY_URL: "http://schema-registry:8081"
      CONNECT_INTERNAL_KEY_CONVERTER: "org.apache.kafka.connect.json.JsonConverter"
      CONNECT_INTERNAL_VALUE_CONVERTER: "org.apache.kafka.connect.json.JsonConverter"
      CONNECT_REST_ADVERTISED_HOST_NAME: "connect"
      CONNECT_LOG4J_ROOT_LOGLEVEL: INFO
      CONNECT_LOG4J_LOGGERS: org.reflections=ERROR
      CONNECT_PLUGIN_PATH: /plugins,/usr/share/java
      CONNECT_REST_HOST_NAME: "connect"

  control-center:
    image: confluentinc/cp-enterprise-control-center:5.5.1
    hostname: control-center
    container_name: control-center
    restart: always
    networks:
      - confluent
    ports:
      - "9021:9021"
    volumes:
      - ./data/control-center/data:/data
    environment:
      CONTROL_CENTER_BOOTSTRAP_SERVERS: kafka-1:9092
      CONTROL_CENTER_ZOOKEEPER_CONNECT: zk-1:2181
      CONTROL_CENTER_DATA_DIR: "/data"
      CONTROL_CENTER_REPLICATION_FACTOR: 1
      CONTROL_CENTER_MONITORING_INTERCEPTOR_TOPIC_REPLICATION: 1
      CONTROL_CENTER_INTERNAL_TOPICS_REPLICATION: 1
      CONTROL_CENTER_COMMAND_TOPIC_REPLICATION: 1
      CONTROL_CENTER_METRICS_TOPIC_REPLICATION: 1
      CONTROL_CENTER_NUM_STREAM_THREADS: 3
      CONTROL_CENTER_STREAMS_CONSUMER_REQUEST_TIMEOUT_MS: "960032"
      CONTROL_CENTER_CONNECT_CLUSTER: "connect:8083"
      #CONTROL_CENTER_KSQL_URL: "http://ksql-server:8088"
      #CONTROL_CENTER_KSQL_ADVERTISED_URL: "http://localhost:8088"
      CONTROL_CENTER_SCHEMA_REGISTRY_URL: "http://schema-registry:8081"

  tools:
    image: cnfltraining/training-tools:5.5
    hostname: tools
    container_name: tools
    volumes:
      - ./data/tools:/data
    networks: 
      - confluent
    command: /bin/sh
    tty: true

  # PostgreSQL database as source
  postgres-source:
    image: debezium/postgres:11
    hostname: postgres-source
    container_name: postgres-source
    volumes:
      - ./data/postgres-source/data:/var/lib/postgresql/data
    networks: 
      - confluent
    ports:
      - 5432:5432
    environment:
      - POSTGRES_DB=user
      - POSTGRES_USER=user
      - POSTGRES_PASSWORD=password

  # PostgreSQL database as target
  postgres-target:
    image: debezium/postgres:11
    hostname: postgres-target
    container_name: postgres-target
    volumes:
      - ./data/postgres-target/data:/var/lib/postgresql/data
    networks: 
      - confluent
    ports:
      - 5433:5432
    environment:
      - POSTGRES_DB=user
      - POSTGRES_USER=user
      - POSTGRES_PASSWORD=password

  pgadmin4:
    image: dpage/pgadmin4:4.24
    hostname: pgadmin4
    container_name: pgadmin4
    networks:
      - confluent
    environment:
      - PGADMIN_DEFAULT_EMAIL=admin
      - PGADMIN_DEFAULT_PASSWORD=admin
    ports:
      - 8888:80

networks:
  confluent:
```
