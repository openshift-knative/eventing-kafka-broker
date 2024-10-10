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

FROM registry.access.redhat.com/ubi8/openjdk-21 as builder

WORKDIR /build

USER root

COPY /data-plane/pom.xml .
COPY /data-plane/.editorconfig .
COPY /data-plane/core/pom.xml core/pom.xml
COPY /data-plane/receiver/pom.xml receiver/pom.xml
COPY /data-plane/receiver-loom/pom.xml receiver-loom/pom.xml
COPY /data-plane/dispatcher/pom.xml dispatcher/pom.xml
COPY /data-plane/dispatcher-loom/pom.xml dispatcher-loom/pom.xml
COPY /data-plane/contract/pom.xml contract/pom.xml
COPY /data-plane/mvnw .
COPY /data-plane/.mvn/wrapper .mvn/wrapper

# Install dependencies. Note: don't build a single submodule (receiver or dispatcher) since it just slows down
# consecutive builds.
RUN ./mvnw install -am -DskipTests -Drelease -Dlicense.skip -Deditorconfig.skip --no-transfer-progress

COPY /data-plane/ .

RUN ./mvnw package -pl=dispatcher-loom -Drelease -am -DskipTests -Deditorconfig.skip --no-transfer-progress

RUN mkdir /app && cp /build/dispatcher-loom/target/dispatcher-loom-1.0-SNAPSHOT.jar /app/app.jar

# We use the generated JDK from the "builder" image, so we can just go with the ubi-minimal
FROM registry.access.redhat.com/ubi8/openjdk-21-runtime as running

EXPOSE 8080 8778 9779

USER 185

LABEL \
      com.redhat.component="openshift-serverless-1-eventing-kafka-broker-dispatcher-rhel8-container" \
      name="openshift-serverless-1/eventing-kafka-broker-dispatcher-rhel8" \
      version=$VERSION \
      summary="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Dispatcher" \
      maintainer="serverless-support@redhat.com" \
      description="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Dispatcher" \
      io.k8s.display-name="Red Hat OpenShift Serverless 1 Eventing Kafka Broker Dispatcher" \
      io.k8s.description="Red Hat OpenShift Serverless Eventing Kafka Broker Dispatcher" \
      io.openshift.tags=Dispatcher

COPY --from=builder /app /app

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
