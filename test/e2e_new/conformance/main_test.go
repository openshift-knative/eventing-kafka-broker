//go:build e2e || deletecm
// +build e2e deletecm

/*
 * Copyright 2023 The Knative Authors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package conformance

import (
	"fmt"
	"log"
	"os"
	"testing"

	// Uncomment the following line to load the gcp plugin (only required to authenticate against GKE clusters).
	_ "k8s.io/client-go/plugin/pkg/client/auth/gcp"

	_ "knative.dev/pkg/system/testing"
	"knative.dev/pkg/test/zipkin"

	"knative.dev/eventing/pkg/apis/eventing"
	"knative.dev/eventing/test/rekt/resources/broker"
	"knative.dev/reconciler-test/pkg/environment"

	"knative.dev/eventing-kafka-broker/control-plane/pkg/kafka"
)

var global environment.GlobalEnvironment

// TestMain is the first entry point for `go test`.
func TestMain(m *testing.M) {
	// Force the broker class to be configured properly
	if broker.EnvCfg.BrokerClass != kafka.BrokerClass && broker.EnvCfg.BrokerClass != kafka.NamespacedBrokerClass && broker.EnvCfg.BrokerClass != eventing.MTChannelBrokerClassValue {
		panic(fmt.Errorf("KafkaBroker class '%s' is unknown. Specify 'BROKER_CLASS' env var", broker.EnvCfg.BrokerClass))
	}

	global = environment.NewStandardGlobalEnvironment()

	// Run the tests.
	os.Exit(func() int {
		defer zipkin.CleanupZipkinTracingSetup(log.Printf)
		return m.Run()
	}())
}
