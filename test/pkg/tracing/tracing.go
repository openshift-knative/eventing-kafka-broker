package tracing

import (
	"context"
	"fmt"
	"regexp"
	"time"

	cetest "github.com/cloudevents/sdk-go/v2/test"
	"github.com/openzipkin/zipkin-go/model"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
	pkgtracing "knative.dev/pkg/test/tracing"
	pkgzipkin "knative.dev/pkg/test/zipkin"
	"knative.dev/reconciler-test/pkg/eventshub"
)

func TraceTreeMatches(sourceName, eventID string, expectedTraceTree pkgtracing.TestSpanTree) eventshub.EventInfoMatcher {
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

func WithMessageIDSource(eventID, sourceName string) pkgtracing.SpanMatcherOption {
	return func(m *pkgtracing.SpanMatcher) {
		m.Tags = map[string]*regexp.Regexp{
			"messaging.message_id":     regexp.MustCompile("^" + eventID + "$"),
			"messaging.message_source": regexp.MustCompile("^" + sourceName + "$"),
		}
	}
}
