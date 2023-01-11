//go:build e2e
// +build e2e

/*
 * Copyright 2022 The Knative Authors
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

package e2e_new

import (
	"fmt"
	"testing"

	"knative.dev/pkg/system"
	"knative.dev/reconciler-test/pkg/environment"
	"knative.dev/reconciler-test/pkg/k8s"
	"knative.dev/reconciler-test/pkg/knative"

	"knative.dev/eventing-kafka-broker/test/e2e_new/features"
)

func TestKafkaSourceCreateSecretsAfterKafkaSource(t *testing.T) {

	t.Parallel()

	ctx, env := global.Environment(
		knative.WithKnativeNamespace(system.Namespace()),
		knative.WithLoggingConfig,
		knative.WithTracingConfig,
		k8s.WithEventListener,
		environment.Managed(t),
	)

	env.Test(ctx, t, features.CreateSecretsAfterKafkaSource())
}

func TestKafkaSourceRepeatedlyCreatedDeleted(t *testing.T) {

	// Always use the same namespace for multiple tests
	namespace := "kafka-source-deleted-recreated"

	t.Parallel()

	for i := 0; i < 10; i++ {
		t.Run(fmt.Sprintf("%d", i), func(t *testing.T) {
			// Note: don't call t.Parallel() here since each test run will conflict with each other

			ctx, env := global.Environment(
				knative.WithKnativeNamespace(system.Namespace()),
				knative.WithLoggingConfig,
				knative.WithTracingConfig,
				k8s.WithEventListener,
				environment.InNamespace(namespace),
				environment.WithTestLogger(t),
			)

			env.Test(ctx, t, features.SetupNamespace(namespace))
			env.Test(ctx, t, features.SetupAndCleanupKafkaSources(fmt.Sprintf("%d-kafka-source-", i), 50))
		})
	}

	t.Cleanup(func() {
		ctx, env := global.Environment(
			knative.WithKnativeNamespace(system.Namespace()),
			knative.WithLoggingConfig,
			knative.WithTracingConfig,
			k8s.WithEventListener,
			environment.InNamespace(namespace),
			environment.WithTestLogger(t),
		)

		env.Test(ctx, t, features.CleanupNamespace(namespace))
	})
}
