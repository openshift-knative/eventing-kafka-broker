//go:build e2e
// +build e2e

/*
 * Copyright 2021 The Knative Authors
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
	"context"
	"fmt"
	"regexp"
	"testing"
	"time"

	cetest "github.com/cloudevents/sdk-go/v2/test"
	"github.com/openzipkin/zipkin-go/model"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
	"knative.dev/eventing/test/rekt/resources/broker"
	"knative.dev/eventing/test/rekt/resources/trigger"
	"knative.dev/pkg/system"
	pkgtracing "knative.dev/pkg/test/tracing"
	pkgzipkin "knative.dev/pkg/test/zipkin"
	"knative.dev/reconciler-test/pkg/environment"
	"knative.dev/reconciler-test/pkg/eventshub"
	"knative.dev/reconciler-test/pkg/feature"
	"knative.dev/reconciler-test/pkg/k8s"
	"knative.dev/reconciler-test/pkg/knative"
	"knative.dev/reconciler-test/resources/svc"

	. "knative.dev/reconciler-test/pkg/eventshub/assert"

	"knative.dev/eventing-kafka-broker/control-plane/pkg/kafka"
	"knative.dev/eventing-kafka-broker/test/pkg/tracing"
)

func TestTracingHeaders(t *testing.T) {
	t.Parallel()

	ctx, env := global.Environment(
		knative.WithKnativeNamespace(system.Namespace()),
		knative.WithLoggingConfig,
		knative.WithTracingConfig,
		k8s.WithEventListener,
		tracing.WithZipkin,
		environment.Managed(t),
	)

	env.Test(ctx, t, TracingHeadersUsingOrderedDeliveryWithTraceExported())
	env.Test(ctx, t, TracingHeadersUsingUnorderedDelivery())
	env.Test(ctx, t, TracingHeadersUsingUnorderedDeliveryWithMultipleTriggers())
}

func TracingHeadersUsingOrderedDeliveryWithTraceExported() *feature.Feature {
	f := feature.NewFeature()

	sourceName := feature.MakeRandomK8sName("source")
	sinkName := feature.MakeRandomK8sName("sink")
	triggerName := feature.MakeRandomK8sName("trigger")
	brokerName := feature.MakeRandomK8sName("broker")

	ev := cetest.FullEvent()
	ev.SetID("full-event-ordered")
	ev.SetSource(sourceName)

	f.Setup("install broker", broker.Install(
		brokerName,
		broker.WithBrokerClass(kafka.BrokerClass),
	))
	f.Setup("broker is ready", broker.IsReady(brokerName))
	f.Setup("broker is addressable", broker.IsAddressable(brokerName))

	f.Setup("install sink", eventshub.Install(
		sinkName,
		eventshub.StartReceiver,
	))
	f.Setup("install trigger", trigger.Install(
		triggerName,
		brokerName,
		trigger.WithSubscriber(svc.AsKReference(sinkName), ""),
		trigger.WithAnnotation("kafka.eventing.knative.dev/delivery.order", "ordered"),
	))
	f.Setup("trigger is ready", trigger.IsReady(triggerName))

	f.Requirement("install source", eventshub.Install(
		sourceName,
		eventshub.StartSenderToResource(broker.GVR(), brokerName),
		eventshub.InputEvent(ev),
		eventshub.AddTracing,
		// Send at least two events to workaround https://github.com/knative/pkg/issues/2475.
		// There's some time needed for exporting the trace to Zipkin. Sending two events with
		// some delay gives the exporter time to export the trace for the first event. The sender
		// is shutdown immediately after sending the last event so the trace for the last
		// event will probably not be exported.
		eventshub.SendMultipleEvents(2, 3*time.Second),
	))

	f.Assert("received event has traceparent header",
		OnStore(sinkName).
			Match(MatchKind(EventReceived), hasTraceparentHeader).
			AtLeast(1),
	)

	f.Assert("event trace exported", hasMatchingTraceTree(sourceName, sinkName, brokerName, ev.ID()))

	return f
}

func hasMatchingTraceTree(sourceName, sinkName, brokerName, eventID string) func(ctx context.Context, t feature.T) {
	return func(ctx context.Context, t feature.T) {
		testNS := environment.FromContext(ctx).Namespace()
		systemNS := knative.KnativeNamespaceFromContext(ctx)
		expectedTree := pkgtracing.TestSpanTree{
			Note: "1. Send pod sends event to the Broker Ingress",
			Span: pkgtracing.MatchHTTPSpanNoReply(
				model.Client,
				pkgtracing.WithHTTPURL(
					fmt.Sprintf("kafka-broker-ingress.%s.svc", systemNS),
					fmt.Sprintf("/%s/%s", testNS, brokerName),
				),
				pkgtracing.WithLocalEndpointServiceName(sourceName),
			),
			Children: []pkgtracing.TestSpanTree{
				{
					Note: "2. Kafka Broker Receiver getting the message",
					Span: pkgtracing.MatchHTTPSpanNoReply(
						model.Server,
						pkgtracing.WithLocalEndpointServiceName("kafka-broker-receiver"),
						withMessageIDSource(eventID, sourceName),
					),
					Children: []pkgtracing.TestSpanTree{
						{
							Note: "3. Kafka Broker Receiver storing message to Kafka",
							Span: pkgtracing.MatchSpan(
								model.Producer,
								pkgtracing.WithLocalEndpointServiceName("kafka-broker-receiver"),
							),
							Children: []pkgtracing.TestSpanTree{
								{
									Note: "4. Kafka Broker Dispatcher reading message from Kafka",
									Span: pkgtracing.MatchSpan(
										model.Consumer,
										pkgtracing.WithLocalEndpointServiceName("kafka-broker-dispatcher"),
										withMessageIDSource(eventID, sourceName),
									),
									Children: []pkgtracing.TestSpanTree{
										{
											Note: "5. Kafka Broker Dispatcher sending message to sink",
											Span: pkgtracing.MatchHTTPSpanNoReply(
												model.Client,
												pkgtracing.WithHTTPURL(
													fmt.Sprintf("%s.%s.svc", sinkName, testNS),
													"/",
												),
												pkgtracing.WithLocalEndpointServiceName("kafka-broker-dispatcher"),
											),
											Children: []pkgtracing.TestSpanTree{
												{
													Note: "6. The target Pod receiving message",
													Span: pkgtracing.MatchHTTPSpanNoReply(
														model.Server,
														pkgtracing.WithHTTPHostAndPath(
															fmt.Sprintf("%s.%s.svc", sinkName, testNS),
															"/",
														),
														pkgtracing.WithLocalEndpointServiceName(sinkName),
													),
												},
											},
										},
									},
								},
							},
						},
					},
				},
			},
		}
		eventshub.StoreFromContext(ctx, sinkName).AssertAtLeast(t, 1,
			MatchKind(EventReceived),
			traceTreeMatches(sourceName, eventID, expectedTree),
		)
	}
}

func withMessageIDSource(eventID, sourceName string) pkgtracing.SpanMatcherOption {
	return func(m *pkgtracing.SpanMatcher) {
		m.Tags = map[string]*regexp.Regexp{
			"messaging.message_id":     regexp.MustCompile("^" + eventID + "$"),
			"messaging.message_source": regexp.MustCompile("^" + sourceName + "$"),
		}
	}
}

func TracingHeadersUsingUnorderedDelivery() *feature.Feature {
	f := feature.NewFeature()

	sourceName := feature.MakeRandomK8sName("source")
	sinkName := feature.MakeRandomK8sName("sink")
	triggerName := feature.MakeRandomK8sName("trigger")
	brokerName := feature.MakeRandomK8sName("broker")

	ev := cetest.FullEvent()
	ev.SetID("full-event-unordered")

	f.Setup("install broker", broker.Install(
		brokerName,
		broker.WithBrokerClass(kafka.BrokerClass),
	))
	f.Setup("broker is ready", broker.IsReady(brokerName))
	f.Setup("broker is addressable", broker.IsAddressable(brokerName))

	f.Setup("install sink", eventshub.Install(
		sinkName,
		eventshub.StartReceiver,
	))
	f.Setup("install trigger", trigger.Install(
		triggerName,
		brokerName,
		trigger.WithSubscriber(svc.AsKReference(sinkName), ""),
	))
	f.Setup("trigger is ready", trigger.IsReady(triggerName))

	f.Requirement("install source", eventshub.Install(
		sourceName,
		eventshub.StartSenderToResource(broker.GVR(), brokerName),
		eventshub.InputEvent(ev),
		eventshub.AddTracing,
	))

	f.Assert("received event has traceparent header",
		OnStore(sinkName).
			Match(MatchKind(EventReceived), hasTraceparentHeader).
			Exact(1),
	)

	return f
}

func TracingHeadersUsingUnorderedDeliveryWithMultipleTriggers() *feature.Feature {
	f := feature.NewFeature()

	sourceName := feature.MakeRandomK8sName("source")
	sinkName := feature.MakeRandomK8sName("sink")
	triggerAName := feature.MakeRandomK8sName("trigger-a")
	triggerBName := feature.MakeRandomK8sName("trigger-b")
	brokerName := feature.MakeRandomK8sName("broker")

	ev := cetest.FullEvent()
	ev.SetID("full-event-unordered")

	f.Setup("install broker", broker.Install(
		brokerName,
		broker.WithBrokerClass(kafka.BrokerClass),
	))
	f.Setup("broker is ready", broker.IsReady(brokerName))
	f.Setup("broker is addressable", broker.IsAddressable(brokerName))

	f.Setup("install sink", eventshub.Install(
		sinkName,
		eventshub.StartReceiver,
	))
	f.Setup("install trigger a", trigger.Install(
		triggerAName,
		brokerName,
		trigger.WithSubscriber(svc.AsKReference(sinkName), ""),
	))
	f.Setup("install trigger b", trigger.Install(
		triggerBName,
		brokerName,
		trigger.WithSubscriber(svc.AsKReference(sinkName), ""),
	))
	f.Setup("trigger is ready", trigger.IsReady(triggerAName))

	f.Requirement("install source", eventshub.Install(
		sourceName,
		eventshub.StartSenderToResource(broker.GVR(), brokerName),
		eventshub.InputEvent(ev),
		eventshub.AddTracing,
		eventshub.SendMultipleEvents(5, time.Millisecond),
	))

	f.Assert("received event has traceparent header",
		OnStore(sinkName).
			Match(MatchKind(EventReceived), hasTraceparentHeader).
			Exact(10),
	)

	return f
}

func hasTraceparentHeader(info eventshub.EventInfo) error {
	if _, ok := info.HTTPHeaders["Traceparent"]; !ok {
		return fmt.Errorf("HTTP Headers does not contain the 'Traceparent' header")
	}
	return nil
}

func traceTreeMatches(sourceName, eventID string, expectedTraceTree pkgtracing.TestSpanTree) eventshub.EventInfoMatcher {
	return func(info eventshub.EventInfo) error {
		if err := cetest.AllOf(
			cetest.HasSource(sourceName),
			cetest.HasId(eventID))(*info.Event); err != nil {
			return err
		}
		traceID, err := getTraceIDHeader(info)
		if err != nil {
			return err
		}
		trace, err := pkgzipkin.JSONTracePred(traceID, 5*time.Second, func(trace []model.SpanModel) bool {
			tree, err := pkgtracing.GetTraceTree(trace)
			if err != nil {
				return false
			}
			return len(expectedTraceTree.MatchesSubtree(nil, tree)) > 0
		})
		if err != nil {
			tree, err := pkgtracing.GetTraceTree(trace)
			if err != nil {
				return err
			}
			if len(expectedTraceTree.MatchesSubtree(nil, tree)) == 0 {
				return fmt.Errorf("no matching subtree. want: %v got: %v", expectedTraceTree, tree)
			}
		}
		return nil
	}
}

// TODO: Move this to a common package or knative/pkg.
// getTraceIDHeader gets the TraceID from the passed event. It returns an error
// if trace id is not present in that message.
func getTraceIDHeader(info eventshub.EventInfo) (string, error) {
	if info.HTTPHeaders != nil {
		sc := trace.SpanContextFromContext(propagation.TraceContext{}.Extract(context.TODO(), propagation.HeaderCarrier(info.HTTPHeaders)))
		if sc.HasTraceID() {
			return sc.TraceID().String(), nil
		}
	}
	return "", fmt.Errorf("no traceid in info: (%v)", info)
}
