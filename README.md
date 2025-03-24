# Openshift Knative Eventing Kafka


### Midstream development - Quarkus version

A note how to fetch and verify version string for latest Red Hat's Quarkus release.

Latest exact version of RHBQ available:
```bash
curl -s "https://code.quarkus.redhat.com/api/platforms" | jq -r '.platforms[0].streams[0].releases[0].version'
```

Latest exact version of versioned stream (where `id` is equal to major.minor version):
```bash
curl -s "https://code.quarkus.redhat.com/api/platforms" | jq -r '.platforms[0].streams[] | select (.id=="3.8") | .releases[0].version'
```