#
# Copyright © 2018 Knative Authors (knative-dev@googlegroups.com)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

ARG JAVA_BUILDER=registry.access.redhat.com/ubi8/openjdk-21
ARG JAVA_RUNTIME=registry.access.redhat.com/ubi8/openjdk-21-runtime
ARG DEPS_IMAGE
ARG VERSION=""

FROM $DEPS_IMAGE AS deps

FROM $JAVA_BUILDER AS builder

USER root

WORKDIR /build

COPY --from=deps /third_party/maven/ /third_party/maven/

COPY /data-plane .

RUN mvn -Dmaven.repo.local=/third_party/maven --offline package -pl=receiver-loom -Drelease -am -DskipTests --no-transfer-progress

RUN mkdir /app && cp /build/receiver-loom/target/receiver-loom-1.0-SNAPSHOT.jar /app/app.jar

FROM $JAVA_RUNTIME AS running

USER 185

LABEL \
      com.redhat.component="openshift-serverless-1-eventing-kafka-broker-receiver-rhel8-container" \
      name="openshift-serverless-1/eventing-kafka-broker-receiver-rhel8" \
      version=$VERSION \
      summary="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Receiver" \
      maintainer="serverless-support@redhat.com" \
      description="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Receiver" \
      io.k8s.display-name="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Receiver" \
      io.k8s.description="Red Hat OpenShift Serverless Eventing Kafka Broker Receiver" \
      io.openshift.tags=receiver

COPY --from=builder /app /app

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
