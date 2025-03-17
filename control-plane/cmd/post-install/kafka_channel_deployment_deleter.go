/*
 * Copyright 2024 The Knative Authors
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

package main

import (
	"context"
	"fmt"

	"knative.dev/pkg/logging"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes"
)

type kafkaDeploymentDeleter struct {
	k8s kubernetes.Interface
}

func (k *kafkaDeploymentDeleter) DeleteChannelDeployments(ctx context.Context) error {
	logger := logging.FromContext(ctx)
	logger.Info("Deleting Kafka Channel Deployments")

	deployments := []string{
		"kafka-channel-dispatcher",
	}

	for _, deployment := range deployments {
		logger.Infof("Checking if deployment %s exists", deployment)
		// if the deployment does not exist, we can skip the deletion
		_, err := k.k8s.AppsV1().Deployments("knative-eventing").Get(ctx, deployment, metav1.GetOptions{})
		if err != nil {
			if apierrors.IsNotFound(err) {
				logger.Infof("Deployment %s not found, skipping deletion", deployment)
				continue
			}
			logger.Errorf("Failed to get deployment %s: %v", deployment, err)
			return fmt.Errorf("failed to get deployment %s: %w", deployment, err)
		}

		logger.Infof("Deleting deployment %s", deployment)
		if err := k.deleteDeployment(ctx, types.NamespacedName{Name: deployment, Namespace: "knative-eventing"}); err != nil {
			return fmt.Errorf("failed to delete deployment %s: %v", deployment, err)
		}
	}

	return nil
}
