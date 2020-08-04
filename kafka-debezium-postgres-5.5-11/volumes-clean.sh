#!/bin/bash

rm -rf data/zk-1/log/*
rm -rf data/zk-1/data/*

rm -rf data/kafka-1/data/*
rm -rf data/control-center/data/*
rm -rf data/connect/data/*
# rm -rf data/connect/plugins/*
rm -rf data/tools/data/*

rm -rf data/postgres-source
rm -rf data/pgadmin4
