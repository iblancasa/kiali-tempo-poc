// The jsonnet file used to generate the Kubernetes manifests.
local tempo = import 'microservices/tempo.libsonnet';
local k = import 'ksonnet-util/kausal.libsonnet';
local container = k.core.v1.container;
local containerPort = k.core.v1.containerPort;

tempo {
    _images+:: {
        tempo: 'grafana/tempo:latest',
        tempo_query: 'grafana/tempo-query:latest',
    },

    tempo_distributor_container+:: container.withPorts([
            containerPort.new('jaeger-grpc', 14250),
            containerPort.new('otlp-grpc', 4317),
        ]),

    _config+:: {
        namespace: 'tempo',

        compactor+: {
            replicas: 1,
        },
        query_frontend+: {
            replicas: 1,
        },
        querier+: {
            replicas: 1,
        },
        ingester+: {
            replicas: 1,
            pvc_size: '1Gi',
            pvc_storage_class: 'standard',
            lifecycler: {
                ring: {
                replication_factor: 1,
                },
            },
        },
        distributor+: {
            replicas: 1,
            receivers: {
                jaeger: {
                    protocols: {
                        grpc: {
                            endpoint: '0.0.0.0:14250',
                        },
                    },
                },
                otlp: {
                    protocols: {
                        grpc: {
                            endpoint: '0.0.0.0:4317',
                        },
                    },
                },
            },
        },

        metrics_generator+: {
            replicas: 1,
            ephemeral_storage_request_size: '3Gi',
            ephemeral_storage_limit_size: '6Gi',
        },
        memcached+: {
            replicas: 1,
        },

        bucket: 'tempo-data',
        backend: 's3',
    },

    tempo_config+:: {
        storage+: {
            trace+: {
                s3: {
                    bucket: $._config.bucket,
                    access_key: 'minio',
                    secret_key: 'minio123',
                    endpoint: 'minio:9000',
                    insecure: true,
                },
            },
        },
        metrics_generator+: {
            processor: {
                span_metrics: {},
                service_graphs: {},
            },

            registry+: {
                external_labels: {
                    source: 'tempo',
                },
            },
        },
        overrides+: {
            max_search_bytes_per_trace: 5000000,
            metrics_generator_processors: ['service-graphs', 'span-metrics'],
        },
    },
    tempo_ingester_container+:: {
        resources+: {
            limits+: {
                cpu: '3',
                memory: '5Gi',
            },
            requests+: {
                cpu: '200m',
                memory: '2Gi',
            },
        },
    },

    local statefulSet = $.apps.v1.statefulSet,
    tempo_ingester_statefulset+:
        statefulSet.mixin.spec.withPodManagementPolicy('Parallel'),
}
